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
    public var executionLimit: Int

    /// Stack of error handlers for do-catch blocks.
    /// Each entry: (catchIP: bytecode offset to jump to, stackDepth: stack count at pushHandler, callDepth: call stack count)
    private var errorHandlers: [(catchIP: Int, stackDepth: Int, callDepth: Int)] = []
    /// Stack of deferred block addresses (LIFO execution on scope exit).
    private var deferStack: [Int] = []

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

    /// SwiftUI context for @State/@Binding opcodes. Set during view body evaluation.
    public var swiftUIContext: SwiftUIContext?

    /// Bridge registry for host type dispatch. Set by Interpreter.
    public var bridgeMethodLookup: ((String, String) -> ((Value, [Value]) throws -> Value)?)?
    /// Bridge property lookup. Set by Interpreter.
    public var bridgePropertyLookup: ((String, String) -> ((Value) throws -> Value)?)?

    /// Built-in method registry for Array, String, Dictionary, Range, Optional.
    private let builtinMethods = BuiltinMethodRegistry()

    // MARK: - Init

    public init(maxCallDepth: Int = defaultMaxCallDepth, executionLimit: Int = defaultExecutionLimit) {
        self.maxCallDepth = maxCallDepth; self.executionLimit = executionLimit
    }

    // MARK: - Loading

    public func load(_ program: CompiledProgram) {
        self.program = program; ip = 0; stack.reset()
        callStack.removeAll(); errorHandlers.removeAll(); deferStack.removeAll(); executionCount = 0; state = .ready
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
        case .pop:
            let popped = stack.pop()
            // When a view collector is active (inside a container closure),
            // collect view values instead of discarding them.
            if let collector = swiftUIContext?.viewCollector {
                collector.collectView(popped)
            }
            ip += 1
        case .dup: try stack.push(stack.peek()); ip += 1

        // Variables
        case .loadLocal:
            guard let slot = readU16(at: ip + 1) else { throw decodeError() }
            let val = stack[basePointer + Int(slot)]
            // Transparent cell unwrap: read through CaptureCell
            if case .cell(let c) = val { try stack.push(c.value) }
            else { try stack.push(val) }
            ip += 3
        case .storeLocal:
            guard let slot = readU16(at: ip + 1) else { throw decodeError() }
            let idx = basePointer + Int(slot)
            var value = stack.pop()
            // Copy struct instances for value semantics
            if case .instance(let ref) = value, ref.kind == .struct {
                value = .instance(ref.copy())
            }
            while stack.count <= idx { try stack.push(.nil_) }
            stack[idx] = value
            ip += 3
        case .captureLocal:
            // Ensure slot has a CaptureCell, push the .cell itself for CLOSURE
            guard let slot = readU16(at: ip + 1) else { throw decodeError() }
            let idx = basePointer + Int(slot)
            if case .cell(let c) = stack[idx] {
                // Already a cell — push for reuse by CLOSURE
                try stack.push(.cell(c))
            } else {
                // Wrap in new cell, write back, and push
                let cell = CaptureCell(stack[idx])
                stack[idx] = .cell(cell)
                try stack.push(.cell(cell))
            }
            ip += 3
        case .loadGlobal:
            guard let ni = readU16(at: ip + 1), let name = program.constantPool.string(at: ni) else { throw decodeError() }
            guard let v = environment.getGlobal(name) else { throw InterpreterError.undefinedVariable(name, at: loc()) }
            try stack.push(v); ip += 3
        case .storeGlobal:
            guard let ni = readU16(at: ip + 1), let name = program.constantPool.string(at: ni) else { throw decodeError() }
            var value = stack.pop()
            // Copy struct instances for value semantics
            if case .instance(let ref) = value, ref.kind == .struct {
                value = .instance(ref.copy())
            }
            environment.setGlobal(name, value: value); ip += 3
        case .loadCapture:
            guard let idx = readU16(at: ip + 1), let caps = callStack.last?.captures, Int(idx) < caps.count else { throw decodeError() }
            try stack.push(caps[Int(idx)].value); ip += 3
        case .storeCapture:
            guard let idx = readU16(at: ip + 1), let caps = callStack.last?.captures, Int(idx) < caps.count else { throw decodeError() }
            caps[Int(idx)].value = stack.pop(); ip += 3

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
            let rv = stack.pop(); try runDefers(); try returnFromFunction(); try stack.push(rv)
        case .returnVoid:
            try runDefers(); try returnFromFunction(); try stack.push(.void)
        case .closure:
            guard let fi = readU16(at: ip + 1), let cc = readU8(at: ip + 3),
                  let fn = program.constantPool.function(at: fi) else { throw decodeError() }
            var cells: [CaptureCell] = []
            for _ in 0..<cc {
                let val = stack.pop()
                if case .cell(let existingCell) = val {
                    cells.append(existingCell) // Reuse shared cell
                } else {
                    cells.append(CaptureCell(val)) // New cell for globals
                }
            }
            try stack.push(.closure(ClosureRef(function: fn, captures: cells))); ip += 4

        // Properties
        case .getProperty:
            guard let ni = readU16(at: ip + 1), let name = program.constantPool.propertyName(at: ni) else { throw decodeError() }
            let inst = stack.pop()
            try stack.push(getProperty(inst, name: name))
            ip += 3
        case .setProperty:
            guard let ni = readU16(at: ip + 1), let name = program.constantPool.propertyName(at: ni) else { throw decodeError() }
            let val = stack.pop(), inst = stack.pop()
            if case .instance(let ref) = inst {
                // Check if property holds a BindingRef — write through it
                if let existing = ref.property(name),
                   case .hostObject(let hr) = existing, let bindingRef = hr.object as? BindingRef {
                    bindingRef.stateStore.set(bindingRef.key, val)
                }
                // Check for computed property setter
                else if let setter = environment.getGlobal("\(ref.typeName).__set_\(name)") {
                    _ = try invokeValue(setter, args: [inst, val])
                } else {
                    ref.setProperty(name, val)
                }
            }
            ip += 3
        case .getIndex:
            let idx = stack.pop(), col = stack.pop()
            try stack.push(getIndex(col, idx)); ip += 1
        case .setIndex:
            let val = stack.pop(), idx = stack.pop(); var col = stack.pop()
            try setIndex(&col, idx, val); try stack.push(col); ip += 1
        case .callMethod:
            guard let ni = readU16(at: ip + 1), let argc = readU8(at: ip + 3),
                  let methodName = program.constantPool.methodName(at: ni) else { throw decodeError() }
            let mutatingMethods: Set<String> = ["append", "remove", "removeLast", "removeAll", "insert", "removeValue", "removeFirst", "reverse", "sort"]
            let isMutating = mutatingMethods.contains(methodName)
            let handled = try callMethod(methodName, argCount: Int(argc))
            if !handled {
                // For mutating methods on value types, store the result back to the source variable
                if isMutating, let result = stack.peekOptional() {
                    if case .array(_) = result, let _ = result as Value? {
                        // Look backward in bytecode to find the loadLocal/loadGlobal that loaded the receiver
                        let callMethodSize = 4 // opcode + u16 + u8
                        var scanIP = ip
                        // Skip backward past argument-loading instructions
                        // Each arg was loaded before the receiver + args on stack
                        // The receiver was loaded before all args
                        // For arg count 0, receiver is right before callMethod
                        // For arg count N, need to skip N arg-loading instructions
                        // Simple approach: scan back to find last loadLocal/loadGlobal before the args
                        var argsToSkip = Int(argc)
                        var scan = scanIP - 1
                        while scan >= 0 && argsToSkip > 0 {
                            // Find instruction start
                            if let op = Opcode(rawValue: program.bytecode[scan]) {
                                scan -= op.instructionSize
                            } else {
                                scan -= 1
                            }
                            argsToSkip -= 1
                        }
                        // Now scan should point to the instruction that loaded the receiver
                        // Actually, let me try a simpler approach: scan backward from ip
                        let receiverLoadIP = findReceiverLoadIP(at: ip, argCount: Int(argc))
                        if let rip = receiverLoadIP {
                            if program.bytecode[rip] == Opcode.loadLocal.rawValue {
                                let slot = UInt16(program.bytecode[rip + 1]) | (UInt16(program.bytecode[rip + 2]) << 8)
                                let base = callStack.last?.basePointer ?? 0
                                stack.store(at: base + Int(slot), value: result)
                            } else if program.bytecode[rip] == Opcode.loadGlobal.rawValue {
                                let nameIdx = UInt16(program.bytecode[rip + 1]) | (UInt16(program.bytecode[rip + 2]) << 8)
                                if let name = program.constantPool.string(at: nameIdx) {
                                    environment.setGlobal(name, value: result)
                                }
                            }
                        }
                    }
                    if case .dictionary(_) = result {
                        let receiverLoadIP = findReceiverLoadIP(at: ip, argCount: Int(argc))
                        if let rip = receiverLoadIP {
                            if program.bytecode[rip] == Opcode.loadLocal.rawValue {
                                let slot = UInt16(program.bytecode[rip + 1]) | (UInt16(program.bytecode[rip + 2]) << 8)
                                let base = callStack.last?.basePointer ?? 0
                                stack.store(at: base + Int(slot), value: result)
                            } else if program.bytecode[rip] == Opcode.loadGlobal.rawValue {
                                let nameIdx = UInt16(program.bytecode[rip + 1]) | (UInt16(program.bytecode[rip + 2]) << 8)
                                if let name = program.constantPool.string(at: nameIdx) {
                                    environment.setGlobal(name, value: result)
                                }
                            }
                        }
                    }
                }
                ip += 4
            }

        // Host bridge
        case .callHost:
            guard let _ = readU16(at: ip + 1), let _ = readU8(at: ip + 3) else { throw decodeError() }
            ip += 4 // dispatch via bridge registry
        case .construct:
            guard let ti = readU16(at: ip + 1), let argc = readU8(at: ip + 3),
                  let typeName = program.constantPool.typeName(at: ti) else { throw decodeError() }
            // Collect property values from stack
            var props: [(name: String, value: Value)] = []
            // Look up type info to get property names
            if let typeInfo = program.typeTable.first(where: { $0.name == typeName }) {
                var values: [Value] = []
                for _ in 0..<argc { values.insert(stack.pop(), at: 0) }
                for (i, prop) in typeInfo.properties.enumerated() {
                    if i < values.count {
                        props.append((name: prop.name, value: values[i]))
                    } else {
                        // Default value for missing properties based on type annotation
                        let defaultVal: Value
                        switch prop.typeAnnotation {
                        case "Int": defaultVal = .int(0)
                        case "Double", "Float": defaultVal = .double(0.0)
                        case "String": defaultVal = .string("")
                        case "Bool": defaultVal = .bool(false)
                        default: defaultVal = .nil_
                        }
                        props.append((name: prop.name, value: defaultVal))
                    }
                }
            } else {
                // Fallback: unnamed properties
                for i in (0..<Int(argc)).reversed() {
                    props.insert((name: "prop\(i)", value: stack.pop()), at: 0)
                }
            }
            let kind = program.typeTable.first(where: { $0.name == typeName })?.kind ?? .struct
            try stack.push(.instance(InstanceRef(typeName: typeName, kind: kind, properties: props)))
            ip += 4

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
            // Run defers before unwinding
            try runDefers()
            if let handler = errorHandlers.popLast() {
                while stack.count > handler.stackDepth { _ = stack.pop() }
                while callStack.count > handler.callDepth { callStack.removeLast() }
                try stack.push(err)
                ip = handler.catchIP
            } else {
                throw InterpreterError.thrownError(err, at: loc())
            }
        case .pushHandler:
            guard let off = readI16(at: ip + 1) else { throw decodeError() }
            let catchIP = ip + 3 + Int(off)
            errorHandlers.append((catchIP: catchIP, stackDepth: stack.count, callDepth: callStack.count))
            ip += 3
        case .popHandler:
            _ = errorHandlers.popLast()
            ip += 1
        case .deferPush:
            guard let blockAddr = readU16(at: ip + 1) else { throw decodeError() }
            deferStack.append(Int(blockAddr))
            ip += 3
        case .deferPop:
            ip += 1 // no-op; defers run on return

        // SwiftUI state management
        case .stateInit:
            guard let ni = readU16(at: ip + 1), let name = program.constantPool.string(at: ni) else { throw decodeError() }
            let value = stack.pop()
            if let ctx = swiftUIContext, !ctx.stateStore.contains(name) {
                ctx.stateStore.set(name, value)
            }
            ip += 3
        case .stateGet:
            guard let ni = readU16(at: ip + 1), let name = program.constantPool.string(at: ni) else { throw decodeError() }
            if let ctx = swiftUIContext {
                try stack.push(ctx.stateStore.get(name))
            } else {
                try stack.push(.nil_)
            }
            ip += 3
        case .stateSet:
            guard let ni = readU16(at: ip + 1), let name = program.constantPool.string(at: ni) else { throw decodeError() }
            let value = stack.pop()
            swiftUIContext?.stateStore.set(name, value)
            ip += 3
        case .bindingCreate:
            // Create a binding reference that the bridge can convert to Binding<T>
            guard let ni = readU16(at: ip + 1), let name = program.constantPool.string(at: ni) else { throw decodeError() }
            if let ctx = swiftUIContext {
                let ref = BindingRef(stateStore: ctx.stateStore, key: name)
                try stack.push(.hostObject(HostObjectRef(object: ref, typeName: "Binding")))
            } else {
                try stack.push(.nil_)
            }
            ip += 3
        case .publishSet:
            guard let ni = readU16(at: ip + 1), let name = program.constantPool.propertyName(at: ni) else { throw decodeError() }
            let value = stack.pop()
            let instance = stack.pop()
            if case .instance(let ref) = instance {
                ref.setProperty(name, value)
            }
            // Notification is handled by the bridge layer
            ip += 3
        case .viewCollect:
            let view = stack.pop()
            swiftUIContext?.viewCollector?.collectView(view)
            ip += 1
        case .viewGroup:
            guard let count = readU8(at: ip + 1) else { throw decodeError() }
            if let grouped = swiftUIContext?.viewCollector?.groupViews(Int(count)) {
                try stack.push(grouped)
            } else {
                try stack.push(.nil_)
            }
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
        // Numeric comparison
        if let l = a.doubleValue, let r = b.doubleValue {
            try stack.push(.bool(op(l, r))); return
        }
        // String comparison (use same Double op on string comparison result)
        if case .string(let l) = a, case .string(let r) = b {
            let cmp = l < r ? -1.0 : (l > r ? 1.0 : 0.0)
            try stack.push(.bool(op(cmp, 0.0))); return
        }
        throw InterpreterError.typeMismatch("Cannot compare \(a.typeName) and \(b.typeName)", at: loc())
    }

    // MARK: - Functions

    /// returnIP: where to resume after the function returns. Pass nil to use ip + 2 (normal CALL).
    private func callFunction(argCount: Int, returnIP: Int? = nil) throws {
        let callee = stack.peek(argCount)

        switch callee {
        case .nativeFunction(let native):
            var args: [Value] = []
            args.reserveCapacity(argCount)
            for _ in 0..<argCount { args.append(stack.pop()) }
            args.reverse()
            _ = stack.pop() // pop the function itself
            let result = try native.body(args)
            try stack.push(result)
            ip = returnIP ?? (ip + 2)

        case .closure(let ref):
            guard callStack.count < maxCallDepth else {
                throw InterpreterError.stackOverflow(at: loc())
            }
            let bp = stack.count - argCount
            // Type coercion: promote Int→Double for parameters with Double type annotation
            let params = ref.function.parameters
            for i in 0..<min(argCount, params.count) {
                if params[i].typeAnnotation == "Double",
                   case .int(let v) = stack[bp + i] {
                    stack[bp + i] = .double(Double(v))
                }
            }
            let retIP = returnIP ?? (ip + 2)
            let frame = CallFrame(function: ref.function, ip: retIP, basePointer: bp, captures: ref.captures)
            callStack.append(frame)
            // Allocate extra local slots beyond parameters
            let extra = max(0, Int(ref.function.localCount) - argCount)
            for _ in 0..<extra { try stack.push(.nil_) }
            // Jump to function body via stored offset (O(1) dispatch)
            guard ref.function.bytecodeOffset >= 0 else {
                throw InterpreterError.undefinedFunction(ref.function.name, at: loc())
            }
            ip = ref.function.bytecodeOffset

        default:
            throw InterpreterError.notCallable(callee.typeName, at: loc())
        }
    }

    private func returnFromFunction() throws {
        guard let frame = callStack.popLast() else { state = .halted; return }
        // Truncate stack: remove locals, args, and the callee (1 below basePointer)
        stack.truncate(to: max(0, frame.basePointer - 1))
        ip = frame.ip
    }

    // MARK: - Defer Execution

    private func runDefers() throws {
        while let blockAddr = deferStack.popLast() {
            let savedIP = ip
            ip = blockAddr
            // Execute until returnVoid (which the defer block ends with)
            var steps = 0
            while ip < program.bytecode.count {
                steps += 1
                if steps > 10000 { break }
                guard let raw = readU8(at: ip), let opcode = Opcode(rawValue: raw) else { break }
                if opcode == .returnVoid { break } // end of this defer block
                try execute(opcode)
                if case .halted = state { break }
            }
            ip = savedIP
        }
    }

    // MARK: - Value Invocation (for map/filter/reduce callbacks)

    /// Invoke a closure or native function with the given arguments, returning the result.
    /// This saves/restores VM state for re-entrant execution.
    public func invokeValue(_ callable: Value, args: [Value]) throws -> Value {
        switch callable {
        case .nativeFunction(let native):
            return try native.body(args)

        case .closure(let ref):
            // Save current execution state (save indices, not copies)
            let savedIP = ip
            let savedCallDepth = callStack.count
            let savedStackTop = stack.count
            let savedState = state
            state = .running  // Ensure execution loop can run (may be .halted)

            // Push callee + args
            try stack.push(callable)
            for arg in args { try stack.push(arg) }

            // Set up call frame
            let bp = stack.count - args.count
            let retIP = program.bytecode.count // will be past end → stops naturally
            let frame = CallFrame(function: ref.function, ip: retIP, basePointer: bp, captures: ref.captures)
            callStack.append(frame)

            let extra = max(0, Int(ref.function.localCount) - args.count)
            for _ in 0..<extra { try stack.push(.nil_) }

            // Jump to function body via stored offset
            guard ref.function.bytecodeOffset >= 0 else {
                throw InterpreterError.undefinedFunction(ref.function.name, at: loc())
            }
            ip = ref.function.bytecodeOffset

            // Run until return (frame is popped back to saved depth)
            let targetDepth = savedCallDepth
            while callStack.count > targetDepth {
                guard ip < program.bytecode.count else { break }
                guard let raw = readU8(at: ip), let opcode = Opcode(rawValue: raw) else { break }
                executionCount += 1
                if executionCount > executionLimit {
                    throw InterpreterError.executionLimitExceeded(at: loc())
                }
                try execute(opcode)
                if case .halted = state { break }
                if case .error = state { break }
            }

            // Grab the return value (return_ pushes it after truncating)
            let result = stack.count > savedStackTop ? stack.pop() : Value.void

            // Restore state (truncate, don't copy back)
            stack.truncate(to: savedStackTop)
            while callStack.count > savedCallDepth { callStack.removeLast() }
            ip = savedIP
            state = savedState

            return result

        default:
            throw InterpreterError.notCallable(callable.typeName, at: loc())
        }
    }

    // MARK: - Method Calls

    /// Returns true if dispatched to a function (IP already set), false if result pushed and IP needs advancing.
    @discardableResult
    private func callMethod(_ name: String, argCount: Int) throws -> Bool {
        var args: [Value] = []
        args.reserveCapacity(argCount)
        for _ in 0..<argCount { args.append(stack.pop()) }
        args.reverse()
        let receiver = stack.pop()

        // 1. Check built-in method registry (Array, String, Dictionary, Range, Optional)
        if let builtinImpl = builtinMethods.lookup(receiver.builtinTypeName, name) {
            try stack.push(builtinImpl(self, receiver, args))
            return false
        }

        // 2. Optional handling
        if case .optional(.some(let inner)) = receiver {
            if let innerImpl = builtinMethods.lookup(inner.builtinTypeName, name) {
                try stack.push(innerImpl(self, inner, args))
                return false
            }
        } else if case .optional(.none) = receiver {
            try stack.push(.nil_); return false
        } else if case .nil_ = receiver {
            try stack.push(.nil_); return false
        }

        // 3. Type-qualified global lookup (user-defined methods, extensions)
        var lookupTypeName = receiver.typeName
        if case .closure(let ref) = receiver { lookupTypeName = ref.function.name }
        else if case .nativeFunction(let ref) = receiver { lookupTypeName = ref.name }
        let qualifiedName = "\(lookupTypeName).\(name)"
        if let method = environment.getGlobal(qualifiedName) {
            let retIP = ip + 4
            let isStaticCall: Bool
            switch receiver { case .closure, .nativeFunction: isStaticCall = true; default: isStaticCall = false }
            if !isStaticCall {
                try stack.push(method); try stack.push(receiver)
                for arg in args { try stack.push(arg) }
                try callFunction(argCount: args.count + 1, returnIP: retIP)
            } else {
                try stack.push(method)
                for arg in args { try stack.push(arg) }
                try callFunction(argCount: args.count, returnIP: retIP)
            }
            return true
        }
        // 4. Conformance chain
        if let typeInfo = program.typeTable.first(where: { $0.name == receiver.typeName }) {
            for conformance in typeInfo.conformances {
                if let method = environment.getGlobal("\(conformance).\(name)") {
                    try stack.push(method); try stack.push(receiver)
                    for arg in args { try stack.push(arg) }
                    try callFunction(argCount: args.count + 1, returnIP: ip + 4)
                    return true
                }
            }
        }
        // 5. Bridge dispatch
        if let bridgeMethod = bridgeMethodLookup?(receiver.typeName, name) {
            try stack.push(bridgeMethod(receiver, args)); return false
        }
        if case .hostObject = receiver, let bridgeMethod = bridgeMethodLookup?("View", name) {
            try stack.push(bridgeMethod(receiver, args)); return false
        }
        // 6. Extension methods on built-in types (String.reversed2() etc.)
        let extQualified = "\(receiver.builtinTypeName).\(name)"
        if extQualified != qualifiedName, let method = environment.getGlobal(extQualified) {
            try stack.push(method); try stack.push(receiver)
            for arg in args { try stack.push(arg) }
            try callFunction(argCount: args.count + 1, returnIP: ip + 4)
            return true
        }
        throw InterpreterError.undefinedMethod(name, on: receiver.typeName, at: loc())
    }

    // MARK: - Property Access

    private func getProperty(_ value: Value, name: String) throws -> Value {
        switch value {
        case .array(let arr):
            switch name {
            case "count": return .int(arr.count)
            case "isEmpty": return .bool(arr.isEmpty)
            case "first": return .optional(arr.first)
            case "last": return .optional(arr.last)
            // key/value for dictionary sorted() pairs (2-element arrays)
            case "key" where arr.count == 2: return arr[0]
            case "value" where arr.count == 2: return arr[1]
            default: throw InterpreterError.undefinedProperty(name, on: "Array", at: loc())
            }
        case .string(let s):
            switch name {
            case "count": return .int(s.count)
            case "isEmpty": return .bool(s.isEmpty)
            default: throw InterpreterError.undefinedProperty(name, on: "String", at: loc())
            }
        case .dictionary(let d):
            switch name {
            case "count": return .int(d.count)
            case "isEmpty": return .bool(d.isEmpty)
            case "keys": return .array(d.keys.sorted().map { .string($0) })
            case "values": return .array(Array(d.values))
            default: throw InterpreterError.undefinedProperty(name, on: "Dictionary", at: loc())
            }
        case .instance(let ref):
            if let v = ref.property(name) {
                // Transparent binding read: if property holds a BindingRef, read through it
                if case .hostObject(let hr) = v, let bindingRef = hr.object as? BindingRef {
                    return bindingRef.stateStore.get(bindingRef.key)
                }
                return v
            }
            // Check for computed property getter
            let getterName = "\(ref.typeName).__get_\(name)"
            if let getter = environment.getGlobal(getterName) {
                return try invokeValue(getter, args: [value])
            }
            // Fall back to global lookup — inside struct bodies, the compiler may
            // emit getProperty for identifiers like Text, VStack that are actually
            // global type constructors, not properties of self.
            if let global = environment.getGlobal(name) {
                return global
            }
            throw InterpreterError.undefinedProperty(name, on: ref.typeName, at: loc())
        case .enumCase(let ref):
            switch name {
            case "rawValue": return ref.rawValue ?? .nil_
            case "caseName": return .string(ref.caseName)
            case "associatedValues":
                if let av = ref.associatedValues { return .array(av) }
                return .nil_
            default:
                // Check for computed property getter on enum type
                let getterName = "\(ref.typeName).__get_\(name)"
                if let getter = environment.getGlobal(getterName) {
                    return try invokeValue(getter, args: [value])
                }
                throw InterpreterError.undefinedProperty(name, on: ref.typeName, at: loc())
            }
        case .optional(.some(let inner)):
            // Support enum-style pattern matching on optionals
            switch name {
            case "caseName": return .string("some")
            case "associatedValues": return .array([inner])
            default:
                // Optional chaining: unwrap and access property
                let result = try getProperty(inner, name: name)
                return .optional(result)
            }
        case .optional(.none), .nil_:
            switch name {
            case "caseName": return .string("none")
            case "associatedValues": return .array([])
            default:
                // Optional chaining on nil: return nil
                return .nil_
            }
        default:
            // Check for computed property getter from extensions
            let getterName = "\(value.typeName).__get_\(name)"
            if let getter = environment.getGlobal(getterName) {
                return try invokeValue(getter, args: [value])
            }
            // Check bridge registry for property
            if let bridgeGetter = bridgePropertyLookup?(value.typeName, name) {
                return try bridgeGetter(value)
            }
            throw InterpreterError.undefinedProperty(name, on: value.typeName, at: loc())
        }
    }

    // MARK: - Collections

    private func getIndex(_ collection: Value, _ index: Value) throws -> Value {
        switch (collection, index) {
        case (.array(let arr), .int(let i)):
            guard i >= 0 && i < arr.count else { throw InterpreterError.indexOutOfBounds(i, count: arr.count, at: loc()) }
            return arr[i]
        case (.dictionary(let d), .string(let k)): return .optional(d[k])
        case (.dictionary(let d), .int(let i)):
            // Int index: access by position (for for-in iteration)
            let sorted = d.sorted(by: { $0.key < $1.key })
            guard i >= 0 && i < sorted.count else { return .nil_ }
            return .array([.string(sorted[i].key), sorted[i].value])
        case (.dictionary(let d), _):
            let k = index.description; return .optional(d[k])
        case (.nil_, _), (.optional(.none), _):
            return .nil_ // optional chaining on nil returns nil
        case (.optional(.some(let inner)), _):
            return .optional(try getIndex(inner, index))
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
        case (.dictionary(var d), _):
            let k = index.description; d[k] = value; collection = .dictionary(d)
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

    /// Walk backward through bytecode from a callMethod instruction to find the loadLocal/loadGlobal
    /// that loaded the receiver (skipping past argument-loading instructions).
    private func findReceiverLoadIP(at callMethodIP: Int, argCount: Int) -> Int? {
        var pos = callMethodIP
        // Skip backward past argCount worth of instructions
        var toSkip = argCount
        while pos > 0 && toSkip >= 0 {
            // Scan backward to find instruction start
            // Try each possible instruction size
            for size in [9, 4, 3, 2, 1] {
                let candidateIP = pos - size
                if candidateIP >= 0, let op = Opcode(rawValue: program.bytecode[candidateIP]), op.instructionSize == size {
                    pos = candidateIP
                    if toSkip == 0 {
                        // This is the receiver instruction
                        if op == .loadLocal || op == .loadGlobal {
                            return pos
                        }
                        return nil
                    }
                    toSkip -= 1
                    break
                }
            }
            if toSkip >= 0 && pos == callMethodIP { break } // couldn't find instruction
        }
        return nil
    }

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
