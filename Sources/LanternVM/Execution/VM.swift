import Foundation

/// The Lantern stack-based bytecode VM.
public final class VM: @unchecked Sendable {
    public static let defaultMaxCallDepth = 1024
    public static let defaultExecutionLimit = 10_000_000

    // MARK: - State

    public private(set) var stack = ValueStack()
    public private(set) var callStack: [CallFrame] = []
    public private(set) var state: ExecutionState = .ready
    public let environment = Environment()

    private var program: CompiledProgram!
    private var ip: Int = 0
    private var executionCount: Int = 0
    private let maxCallDepth: Int
    private let executionLimit: Int

    // MARK: - Debug hooks

    public weak var delegate: VMDelegate?
    private let pauseCondition = NSCondition()
    private var pauseRequested = false

    /// Set of bytecode offsets with active breakpoints (injected by debugger).
    public var breakpointOffsets: Set<Int> = []
    /// Original opcodes saved when patching breakpoints.
    public var originalOpcodes: [Int: UInt8] = [:]
    /// Stepping state (injected by debugger).
    public var stepMode: StepMode?
    /// When true, the VM pauses on exceptions before propagating. Set by debugger.
    public var breakOnExceptions: Bool = false

    // MARK: - Init

    public init(maxCallDepth: Int = defaultMaxCallDepth, executionLimit: Int = defaultExecutionLimit) {
        self.maxCallDepth = maxCallDepth; self.executionLimit = executionLimit
    }

    // MARK: - Loading

    public func load(_ program: CompiledProgram) {
        self.program = program; ip = 0; stack.reset()
        callStack.removeAll(); executionCount = 0; state = .ready
    }

    // MARK: - Execution Control

    public func run() {
        guard program != nil else { return }
        state = .running; delegate?.vmDidResume(self); executionLoop()
    }

    public func requestPause() { pauseRequested = true }

    public func resume() {
        pauseCondition.lock()
        pauseRequested = false; state = .running
        delegate?.vmDidResume(self)
        pauseCondition.signal(); pauseCondition.unlock()
    }

    // MARK: - Public Inspection

    public var currentIP: Int { ip }
    public var currentSourceLocation: SourceLocation? { program?.sourceMap.location(forOffset: ip) }
    public var currentProgram: CompiledProgram? { program }
    public var stackSnapshot: [Value] { (0..<stack.count).map { stack[$0] } }

    /// Set a value at the given stack index (used by debugger to modify variables).
    public func setStackValue(_ value: Value, at index: Int) {
        precondition(index >= 0 && index < stack.count, "Stack index out of range")
        stack[index] = value
    }

    // MARK: - Execution Loop

    private func executionLoop() {
        let bytecode = program.chunk
        while ip < bytecode.count {
            executionCount += 1
            if executionCount > executionLimit {
                fail(.executionLimitExceeded(at: currentSourceLocation)); return
            }
            if pauseRequested { enterPaused(.userRequested); waitForResume(); continue }

            // Stepping check
            if let mode = stepMode, let loc = currentSourceLocation {
                if shouldPauseForStep(mode, line: loc.line, fileIndex: loc.fileIndex) {
                    stepMode = nil; enterPaused(.step); waitForResume(); continue
                }
            }

            guard let raw = readU8(at: ip), let opcode = Opcode(rawValue: raw) else {
                fail(.init(kind: .custom("invalid_opcode"), message: "Invalid opcode at \(ip)")); return
            }

            do {
                try execute(opcode)
            } catch let error as InterpreterError {
                if breakOnExceptions { enterPaused(.exception(error)); waitForResume() }
                fail(error); return
            } catch {
                fail(.init(kind: .custom("internal"), message: "\(error)")); return
            }

            // Check if execution was terminated by halt or error
            if case .halted = state { return }
            if case .error = state { return }
        }
        state = .halted
    }

    // MARK: - Dispatch

    private func execute(_ opcode: Opcode) throws {
        switch opcode {
        // Constants
        case .constInt:
            guard let v = readI64(at: ip + 1) else { throw decodeError() }
            try stack.push(.int(v)); ip += 9
        case .constDouble:
            guard let v = readF64(at: ip + 1) else { throw decodeError() }
            try stack.push(.double(v)); ip += 9
        case .constBool:
            guard let v = readU8(at: ip + 1) else { throw decodeError() }
            try stack.push(.bool(v != 0)); ip += 2
        case .constString:
            guard let idx = readU16(at: ip + 1), let s = program.constantPool.string(at: idx) else { throw decodeError() }
            try stack.push(.string(s)); ip += 3
        case .constNil:
            try stack.push(.nil_); ip += 1

        // Arithmetic
        case .add: try binaryArith(add); ip += 1
        case .sub: try binaryArith(sub); ip += 1
        case .mul: try binaryArith(mul); ip += 1
        case .div: try binaryArith(divOp); ip += 1
        case .mod: try binaryArith(modOp); ip += 1
        case .neg: try unaryOp(negOp); ip += 1

        // Comparison
        case .eq:  let b = stack.pop(), a = stack.pop(); try stack.push(.bool(a == b)); ip += 1
        case .neq: let b = stack.pop(), a = stack.pop(); try stack.push(.bool(a != b)); ip += 1
        case .lt:  try orderedCmp(<); ip += 1
        case .gt:  try orderedCmp(>); ip += 1
        case .lte: try orderedCmp(<=); ip += 1
        case .gte: try orderedCmp(>=); ip += 1

        // Logic
        case .not:
            let a = stack.pop()
            guard case .bool(let v) = a else { throw InterpreterError.typeMismatch("Expected Bool, got \(a.typeName)", at: loc()) }
            try stack.push(.bool(!v)); ip += 1
        case .and:
            let b = stack.pop(), a = stack.pop()
            guard case .bool(let lb) = a, case .bool(let rb) = b else { throw InterpreterError.typeMismatch("Expected Bool", at: loc()) }
            try stack.push(.bool(lb && rb)); ip += 1
        case .or:
            let b = stack.pop(), a = stack.pop()
            guard case .bool(let lb) = a, case .bool(let rb) = b else { throw InterpreterError.typeMismatch("Expected Bool", at: loc()) }
            try stack.push(.bool(lb || rb)); ip += 1

        // Stack
        case .pop: _ = stack.pop(); ip += 1
        case .dup: try stack.push(stack.peek()); ip += 1

        // Variables
        case .loadLocal:
            guard let slot = readU16(at: ip + 1) else { throw decodeError() }
            try stack.push(stack[basePointer + Int(slot)]); ip += 3
        case .storeLocal:
            guard let slot = readU16(at: ip + 1) else { throw decodeError() }
            let idx = basePointer + Int(slot)
            let value = stack.pop()
            // Ensure the stack extends to cover this slot
            while stack.count <= idx { try stack.push(.nil_) }
            stack[idx] = value
            ip += 3
        case .loadGlobal:
            guard let ni = readU16(at: ip + 1), let name = program.constantPool.string(at: ni) else { throw decodeError() }
            guard let v = environment.getGlobal(name) else { throw InterpreterError.undefinedVariable(name, at: loc()) }
            try stack.push(v); ip += 3
        case .storeGlobal:
            guard let ni = readU16(at: ip + 1), let name = program.constantPool.string(at: ni) else { throw decodeError() }
            environment.setGlobal(name, value: stack.pop()); ip += 3
        case .loadCapture:
            guard let idx = readU16(at: ip + 1), let caps = callStack.last?.captures, Int(idx) < caps.count else { throw decodeError() }
            try stack.push(caps[Int(idx)]); ip += 3
        case .storeCapture:
            _ = readU16(at: ip + 1); _ = stack.pop(); ip += 3

        // Jumps
        case .jump:
            guard let off = readI16(at: ip + 1) else { throw decodeError() }
            ip = ip + 3 + Int(off)
        case .jumpIfTrue:
            guard let off = readI16(at: ip + 1) else { throw decodeError() }
            if stack.pop().isTruthy { ip = ip + 3 + Int(off) } else { ip += 3 }
        case .jumpIfFalse:
            guard let off = readI16(at: ip + 1) else { throw decodeError() }
            if !stack.pop().isTruthy { ip = ip + 3 + Int(off) } else { ip += 3 }
        case .loop:
            guard let off = readI16(at: ip + 1) else { throw decodeError() }
            ip = ip + 3 + Int(off) // off is negative for backward jump

        // Functions
        case .call:
            guard let argc = readU8(at: ip + 1) else { throw decodeError() }
            try callFunction(argCount: Int(argc)); // ip set by call
        case .return_:
            let rv = stack.pop(); try returnFromFunction(); try stack.push(rv)
        case .returnVoid:
            try returnFromFunction()
        case .closure:
            guard let fi = readU16(at: ip + 1), let cc = readU8(at: ip + 3),
                  let fn = program.constantPool.function(at: fi) else { throw decodeError() }
            var caps: [Value] = []; for _ in 0..<cc { caps.append(stack.pop()) }
            try stack.push(.closure(ClosureRef(function: fn, captures: caps))); ip += 4

        // Properties
        case .getProperty:
            guard let ni = readU16(at: ip + 1), let name = program.constantPool.propertyName(at: ni) else { throw decodeError() }
            let inst = stack.pop()
            if case .instance(let ref) = inst, let v = ref.property(name) { try stack.push(v) }
            else { throw InterpreterError.undefinedProperty(name, on: inst.typeName, at: loc()) }
            ip += 3
        case .setProperty:
            guard let ni = readU16(at: ip + 1), let name = program.constantPool.propertyName(at: ni) else { throw decodeError() }
            let val = stack.pop(), inst = stack.pop()
            if case .instance(let ref) = inst { ref.setProperty(name, val) }
            ip += 3
        case .getIndex:
            let idx = stack.pop(), col = stack.pop()
            try stack.push(getIndex(col, idx)); ip += 1
        case .setIndex:
            let val = stack.pop(), idx = stack.pop(); var col = stack.pop()
            try setIndex(&col, idx, val); try stack.push(col); ip += 1
        case .callMethod:
            guard let _ = readU16(at: ip + 1), let _ = readU8(at: ip + 3) else { throw decodeError() }
            ip += 4 // stub — full dispatch via bridge

        // Host bridge
        case .callHost:
            guard let _ = readU16(at: ip + 1), let _ = readU8(at: ip + 3) else { throw decodeError() }
            ip += 4 // dispatch via bridge registry
        case .construct:
            guard let _ = readU16(at: ip + 1), let _ = readU8(at: ip + 3) else { throw decodeError() }
            ip += 4 // dispatch via bridge registry

        // Optionals
        case .wrapOptional: try stack.push(.optional(stack.pop())); ip += 1
        case .unwrapOptional:
            let v = stack.pop()
            switch v {
            case .optional(.some(let inner)): try stack.push(inner)
            case .nil_, .optional(.none): throw InterpreterError.nilUnwrap(at: loc())
            default: try stack.push(v)
            }; ip += 1
        case .optionalChain:
            guard let off = readI16(at: ip + 1) else { throw decodeError() }
            let v = stack.peek()
            if v.isNil { _ = stack.pop(); try stack.push(.nil_); ip = ip + 3 + Int(off) }
            else { ip += 3 }
        case .nilCoalesce:
            let fallback = stack.pop(), v = stack.pop()
            if v.isNil { try stack.push(fallback) }
            else if case .optional(.some(let inner)) = v { try stack.push(inner) }
            else { try stack.push(v) }
            ip += 1

        // Collections
        case .makeArray:
            guard let count = readU16(at: ip + 1) else { throw decodeError() }
            var elems: [Value] = []; for _ in 0..<count { elems.append(stack.pop()) }
            try stack.push(.array(elems.reversed())); ip += 3
        case .makeDict:
            guard let count = readU16(at: ip + 1) else { throw decodeError() }
            var dict: [String: Value] = [:]
            for _ in 0..<count { let v = stack.pop(), k = stack.pop(); if case .string(let s) = k { dict[s] = v } }
            try stack.push(.dictionary(dict)); ip += 3

        // String interpolation
        case .interpolate:
            guard let count = readU8(at: ip + 1) else { throw decodeError() }
            var segs: [Value] = []; for _ in 0..<count { segs.append(stack.pop()) }
            try stack.push(.string(segs.reversed().map(\.description).joined())); ip += 2

        // Range
        case .makeRange:
            guard let inc = readU8(at: ip + 1) else { throw decodeError() }
            let end = stack.pop(), start = stack.pop()
            guard let s = start.intValue, let e = end.intValue else {
                throw InterpreterError.typeMismatch("Expected Int for range bounds", at: loc())
            }
            try stack.push(.range(s, e, inc != 0)); ip += 2

        // Error handling
        case .throw_:
            let err = stack.pop()
            throw InterpreterError.thrownError(err, at: loc())
        case .deferPush:
            guard let _ = readU16(at: ip + 1) else { throw decodeError() }
            ip += 3 // defer registration — stub
        case .deferPop:
            ip += 1 // defer execution — stub

        // SwiftUI state — stubs (implemented by bridge)
        case .stateInit, .stateGet, .stateSet, .bindingCreate, .publishSet:
            ip += 3
        case .viewCollect:
            ip += 1
        case .viewGroup:
            ip += 2

        // Debug
        case .breakpoint:
            let bpRef = BreakpointRef(location: loc() ?? .unknown)
            enterPaused(.breakpoint(bpRef)); waitForResume()
            // Re-execute original opcode
            if let orig = originalOpcodes[ip], let origOp = Opcode(rawValue: orig) {
                try execute(origOp)
            } else { ip += 1 }
        case .halt:
            state = .halted; return
        }
    }

    // MARK: - Arithmetic Helpers

    private func add(_ a: Value, _ b: Value) throws -> Value {
        switch (a, b) {
        case (.int(let l), .int(let r)): return .int(l + r)
        case (.double(let l), .double(let r)): return .double(l + r)
        case (.int(let l), .double(let r)): return .double(Double(l) + r)
        case (.double(let l), .int(let r)): return .double(l + Double(r))
        case (.string(let l), .string(let r)): return .string(l + r)
        default: throw InterpreterError.typeMismatch("Cannot add \(a.typeName) and \(b.typeName)", at: loc())
        }
    }
    private func sub(_ a: Value, _ b: Value) throws -> Value {
        switch (a, b) {
        case (.int(let l), .int(let r)): return .int(l - r)
        case (.double(let l), .double(let r)): return .double(l - r)
        case (.int(let l), .double(let r)): return .double(Double(l) - r)
        case (.double(let l), .int(let r)): return .double(l - Double(r))
        default: throw InterpreterError.typeMismatch("Cannot subtract \(b.typeName) from \(a.typeName)", at: loc())
        }
    }
    private func mul(_ a: Value, _ b: Value) throws -> Value {
        switch (a, b) {
        case (.int(let l), .int(let r)): return .int(l * r)
        case (.double(let l), .double(let r)): return .double(l * r)
        case (.int(let l), .double(let r)): return .double(Double(l) * r)
        case (.double(let l), .int(let r)): return .double(l * Double(r))
        default: throw InterpreterError.typeMismatch("Cannot multiply \(a.typeName) and \(b.typeName)", at: loc())
        }
    }
    private func divOp(_ a: Value, _ b: Value) throws -> Value {
        switch (a, b) {
        case (.int(let l), .int(let r)):
            guard r != 0 else { throw InterpreterError.divisionByZero(at: loc()) }
            return .int(l / r)
        case (.double(let l), .double(let r)): return .double(l / r)
        case (.int(let l), .double(let r)): return .double(Double(l) / r)
        case (.double(let l), .int(let r)):
            guard r != 0 else { throw InterpreterError.divisionByZero(at: loc()) }
            return .double(l / Double(r))
        default: throw InterpreterError.typeMismatch("Cannot divide \(a.typeName) by \(b.typeName)", at: loc())
        }
    }
    private func modOp(_ a: Value, _ b: Value) throws -> Value {
        guard case .int(let l) = a, case .int(let r) = b else {
            throw InterpreterError.typeMismatch("Modulo requires Int operands", at: loc())
        }
        guard r != 0 else { throw InterpreterError.divisionByZero(at: loc()) }
        return .int(l % r)
    }
    private func negOp(_ a: Value) throws -> Value {
        switch a {
        case .int(let v): return .int(-v)
        case .double(let v): return .double(-v)
        default: throw InterpreterError.typeMismatch("Cannot negate \(a.typeName)", at: loc())
        }
    }

    private func binaryArith(_ op: (Value, Value) throws -> Value) throws {
        let b = stack.pop(), a = stack.pop(); try stack.push(op(a, b))
    }
    private func unaryOp(_ op: (Value) throws -> Value) throws {
        try stack.push(op(stack.pop()))
    }
    private func orderedCmp(_ op: (Double, Double) -> Bool) throws {
        let b = stack.pop(), a = stack.pop()
        guard let l = a.doubleValue, let r = b.doubleValue else {
            throw InterpreterError.typeMismatch("Cannot compare \(a.typeName) and \(b.typeName)", at: loc())
        }
        try stack.push(.bool(op(l, r)))
    }

    // MARK: - Functions

    private func callFunction(argCount: Int) throws {
        let callee = stack.peek(argCount)

        switch callee {
        case .nativeFunction(let native):
            // Collect arguments
            var args: [Value] = []
            for _ in 0..<argCount { args.insert(stack.pop(), at: 0) }
            _ = stack.pop() // pop the function itself
            let result = try native.body(args)
            try stack.push(result)
            ip += 2 // advance past CALL opcode

        case .closure(let ref):
            guard argCount >= ref.function.arity && argCount <= ref.function.totalParameterCount else {
                throw InterpreterError.wrongArgumentCount(expected: ref.function.arity, got: argCount, at: loc())
            }
            guard callStack.count < maxCallDepth else {
                throw InterpreterError.stackOverflow(at: loc())
            }
            // Save return address (past the CALL instruction)
            let frame = CallFrame(function: ref.function, ip: ip + 2, basePointer: stack.count - argCount - 1, captures: ref.captures)
            callStack.append(frame)
            let extra = Int(ref.function.localCount) - argCount
            for _ in 0..<extra { try stack.push(.nil_) }
            // Jump to function bytecode offset within the shared program
            // The compiler stores the function's start offset in the bytecodeRange
            // For now, functions compiled inline use offsets into shared bytecode
            if let fnInfo = program.functionTable.first(where: { $0.name == ref.function.name }) {
                ip = fnInfo.bytecodeRange.start
            } else if !ref.function.bytecode.isEmpty {
                // Per-function bytecode not yet supported in shared execution
                ip += 2
            } else {
                ip += 2
            }

        default:
            throw InterpreterError.notCallable(callee.typeName, at: loc())
        }
    }

    private func returnFromFunction() throws {
        guard let frame = callStack.popLast() else { state = .halted; return }
        stack.truncate(to: frame.basePointer); ip = frame.ip
    }

    // MARK: - Collections

    private func getIndex(_ collection: Value, _ index: Value) throws -> Value {
        switch (collection, index) {
        case (.array(let arr), .int(let i)):
            guard i >= 0 && i < arr.count else { throw InterpreterError.indexOutOfBounds(i, count: arr.count, at: loc()) }
            return arr[i]
        case (.dictionary(let d), .string(let k)): return d[k] ?? .nil_
        default: throw InterpreterError.typeMismatch("Cannot subscript \(collection.typeName) with \(index.typeName)", at: loc())
        }
    }
    private func setIndex(_ collection: inout Value, _ index: Value, _ value: Value) throws {
        switch (collection, index) {
        case (.array(var arr), .int(let i)):
            guard i >= 0 && i < arr.count else { throw InterpreterError.indexOutOfBounds(i, count: arr.count, at: loc()) }
            arr[i] = value; collection = .array(arr)
        case (.dictionary(var d), .string(let k)):
            d[k] = value; collection = .dictionary(d)
        default: throw InterpreterError.typeMismatch("Cannot subscript \(collection.typeName)", at: loc())
        }
    }

    // MARK: - Bytecode Reading

    private var program_bytecode: [UInt8] { program.bytecode }
    private func readU8(at offset: Int) -> UInt8? {
        offset < program.bytecode.count ? program.bytecode[offset] : nil
    }
    private func readU16(at offset: Int) -> UInt16? {
        guard offset + 1 < program.bytecode.count else { return nil }
        return UInt16(program.bytecode[offset]) << 8 | UInt16(program.bytecode[offset + 1])
    }
    private func readI16(at offset: Int) -> Int16? {
        guard let u = readU16(at: offset) else { return nil }; return Int16(bitPattern: u)
    }
    private func readI64(at offset: Int) -> Int? {
        guard offset + 7 < program.bytecode.count else { return nil }
        var bits: UInt64 = 0
        for i in 0..<8 { bits = (bits << 8) | UInt64(program.bytecode[offset + i]) }
        return Int(Int64(bitPattern: bits))
    }
    private func readF64(at offset: Int) -> Double? {
        guard offset + 7 < program.bytecode.count else { return nil }
        var bits: UInt64 = 0
        for i in 0..<8 { bits = (bits << 8) | UInt64(program.bytecode[offset + i]) }
        return Double(bitPattern: bits)
    }

    // MARK: - Helpers

    private var basePointer: Int { callStack.last?.basePointer ?? 0 }
    private func loc() -> SourceLocation? { program?.sourceMap.location(forOffset: ip) }
    private func decodeError() -> InterpreterError { .init(kind: .custom("decode"), message: "Failed to decode operand at \(ip)", location: loc()) }
    private func fail(_ error: InterpreterError) { state = .error(error); delegate?.vm(self, didEncounterError: error) }
    private func enterPaused(_ reason: PauseReason) { state = .paused(reason); delegate?.vm(self, didPauseAt: loc() ?? .unknown, reason: reason) }
    private func waitForResume() { pauseCondition.lock(); while case .paused = state { pauseCondition.wait() }; pauseCondition.unlock() }
    private func shouldPauseForStep(_ mode: StepMode, line: UInt32, fileIndex: UInt16) -> Bool {
        switch mode {
        case .over(let depth, let srcLine): return callStack.count <= depth && line != srcLine
        case .into(let srcLine): return line != srcLine
        case .out(let depth): return callStack.count < depth
        case .toLine(let target, let fi): return line == target && fileIndex == fi
        }
    }
}

// MARK: - Step Mode

public enum StepMode: Sendable {
    case over(frameDepth: Int, sourceLine: UInt32)
    case into(sourceLine: UInt32)
    case out(frameDepth: Int)
    case toLine(targetLine: UInt32, fileIndex: UInt16)
}

// MARK: - VM Delegate

public protocol VMDelegate: AnyObject {
    func vm(_ vm: VM, didPauseAt location: SourceLocation, reason: PauseReason)
    func vmDidResume(_ vm: VM)
    func vm(_ vm: VM, didEncounterError error: InterpreterError)
    func vm(_ vm: VM, didProduceOutput text: String)
}

extension VMDelegate {
    public func vm(_ vm: VM, didPauseAt location: SourceLocation, reason: PauseReason) {}
    public func vmDidResume(_ vm: VM) {}
    public func vm(_ vm: VM, didEncounterError error: InterpreterError) {}
    public func vm(_ vm: VM, didProduceOutput text: String) {}
}

// Extension to read bytecode from CompiledProgram as if it were a Chunk
extension CompiledProgram {
    var chunk: [UInt8] { bytecode }
}
