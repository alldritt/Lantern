import Foundation
import LanternVM
import LanternCompiler

/// The main debugger implementation that wraps a VM and compiler.
public final class Debugger: DebuggerInterface, @unchecked Sendable {

    // MARK: - Properties

    public let vm: VM
    private let compiler: BytecodeCompiler
    private var _breakpoints: [UUID: Breakpoint] = [:]
    private var _eventLog: [DebugEvent] = []
    public weak var delegate: DebuggerDelegate?
    public var isBreakOnExceptions: Bool = false

    private var loadedProgram: CompiledProgram?

    // MARK: - Init

    public init(vm: VM = VM(), compiler: BytecodeCompiler = BytecodeCompiler()) {
        self.vm = vm
        self.compiler = compiler
        self.vm.delegate = self
    }

    // MARK: - Program Loading

    public func load(_ program: CompiledProgram) {
        loadedProgram = program
        vm.load(program)
        // Re-apply any enabled breakpoints to the new program.
        reapplyBreakpoints()
    }

    // MARK: - Execution Control

    public func run() {
        vm.run()
    }

    public func startPaused() {
        vm.stepMode = .into(sourceLine: 0)
        vm.run()
    }

    public func pause() {
        vm.requestPause()
    }

    public func stepOver() {
        guard let loc = vm.currentSourceLocation else { vm.resume(); return }
        vm.stepMode = .over(frameDepth: vm.callStack.count, sourceLine: loc.line)
        vm.resume()
    }

    public func stepInto() {
        guard let loc = vm.currentSourceLocation else { vm.resume(); return }
        vm.stepMode = .into(sourceLine: loc.line)
        vm.resume()
    }

    public func stepOut() {
        vm.stepMode = .out(frameDepth: vm.callStack.count)
        vm.resume()
    }

    public func stepToLine(_ line: Int, file: String) {
        guard let program = loadedProgram else { return }
        let fileIndex = program.sourceMap.files.firstIndex(of: file).map(UInt16.init) ?? 0
        vm.stepMode = .toLine(targetLine: UInt32(line), fileIndex: fileIndex)
        vm.resume()
    }

    public var isPaused: Bool {
        if case .paused = vm.state { return true }
        return false
    }

    public var pausedLocation: SourceLocation? {
        guard isPaused else { return nil }
        return vm.currentSourceLocation
    }

    public var pauseReason: PauseReason? {
        if case .paused(let reason) = vm.state { return reason }
        return nil
    }

    // MARK: - Breakpoints

    @discardableResult
    public func addBreakpoint(file: String, line: Int, condition: String?) -> Breakpoint {
        var bp = Breakpoint(
            kind: .line(file: file, line: line),
            condition: condition
        )

        if let program = loadedProgram {
            resolveBreakpoint(&bp, in: program)
        }

        _breakpoints[bp.id] = bp
        syncBreakpointsToVM()
        return bp
    }

    public func removeBreakpoint(_ id: UUID) {
        guard let bp = _breakpoints.removeValue(forKey: id) else { return }
        unpatchBreakpoint(bp)
        syncBreakpointsToVM()
    }

    public func enableBreakpoint(_ id: UUID, enabled: Bool) {
        guard var bp = _breakpoints[id] else { return }
        bp.isEnabled = enabled
        _breakpoints[id] = bp
        syncBreakpointsToVM()
    }

    @discardableResult
    public func addWatchpoint(variable: String, inFrame frameIndex: Int?) -> Breakpoint {
        let bp = Breakpoint(
            kind: .watchpoint(variable: variable, frameIndex: frameIndex)
        )
        _breakpoints[bp.id] = bp
        return bp
    }

    @discardableResult
    public func addHostCallBreakpoint(functionName: String, timing: HostCallBreakpointTiming) -> Breakpoint {
        let bp = Breakpoint(
            kind: .hostCall(functionName: functionName, timing: timing)
        )
        _breakpoints[bp.id] = bp
        return bp
    }

    public var breakpoints: [Breakpoint] {
        Array(_breakpoints.values)
    }

    // MARK: - Inspection

    public var lastExpressionResult: Value? {
        guard isPaused else { return nil }
        return vm.stackSnapshot.last
    }

    public func callStack() -> [FrameInfo] {
        var frames: [FrameInfo] = []
        let vmCallStack = vm.callStack

        if vmCallStack.isEmpty {
            // Synthesize a "main" frame for top-level code
            let isRunning: Bool
            if case .running = vm.state { isRunning = true } else { isRunning = false }
            if isPaused || isRunning {
                frames.append(FrameInfo(
                    functionName: "<main>",
                    sourceLocation: vm.currentSourceLocation,
                    frameIndex: 0,
                    isHostFrame: false,
                    arguments: []
                ))
            }
            return frames
        }

        for (index, frame) in vmCallStack.enumerated().reversed() {
            let location: SourceLocation?
            if index == vmCallStack.count - 1 {
                location = vm.currentSourceLocation
            } else {
                location = loadedProgram?.sourceMap.location(forOffset: frame.ip)
            }

            var args: [(label: String?, value: Value)] = []
            for (paramIndex, param) in frame.function.parameters.enumerated() {
                let slotIndex = frame.basePointer + paramIndex
                let value: Value = (slotIndex < vm.stack.count) ? vm.stack[slotIndex] : .nil_
                args.append((label: param.label, value: value))
            }

            frames.append(FrameInfo(
                functionName: frame.function.name,
                sourceLocation: location,
                frameIndex: index,
                isHostFrame: false,
                arguments: args
            ))
        }

        return frames
    }

    public func locals(frameIndex: Int) -> [VariableInfo] {
        guard let program = loadedProgram else { return [] }
        let vmCallStack = vm.callStack

        let basePointer: Int
        let currentOffset: Int

        if vmCallStack.isEmpty {
            // Synthetic main frame — top-level code uses basePointer 0
            guard frameIndex == 0 else { return [] }
            basePointer = 0
            currentOffset = vm.currentIP
        } else {
            guard frameIndex >= 0 && frameIndex < vmCallStack.count else { return [] }
            let frame = vmCallStack[frameIndex]
            basePointer = frame.basePointer
            currentOffset = (frameIndex == vmCallStack.count - 1) ? vm.currentIP : frame.ip
        }

        var result: [VariableInfo] = []
        for record in program.variableTable where record.isInScope(at: currentOffset) {
            let slotIndex = basePointer + Int(record.slotIndex)
            guard slotIndex >= 0 && slotIndex < vm.stack.count else { continue }
            let value = vm.stack[slotIndex]
            result.append(VariableInfo(
                name: record.name,
                value: value,
                typeName: record.typeAnnotation ?? value.typeName,
                isMutable: record.isMutable,
                scopeDepth: 0
            ))
        }
        return result
    }

    public func captures(frameIndex: Int) -> [VariableInfo] {
        let vmCallStack = vm.callStack
        // Synthetic main frame has no captures
        if vmCallStack.isEmpty { return [] }
        guard frameIndex >= 0 && frameIndex < vmCallStack.count else { return [] }

        let frame = vmCallStack[frameIndex]
        guard let caps = frame.captures else { return [] }

        return caps.enumerated().map { index, cell in
            VariableInfo(
                name: "capture_\(index)",
                value: cell.value,
                typeName: cell.value.typeName,
                isMutable: false,
                scopeDepth: 0
            )
        }
    }

    public func globals() -> [VariableInfo] {
        vm.environment.allGlobals().map { name, value in
            VariableInfo(
                name: name,
                value: value,
                typeName: value.typeName,
                isMutable: true,
                scopeDepth: 0
            )
        }
    }

    public func evaluate(expression: String, inFrame frameIndex: Int) -> Result<Value, InterpreterError> {
        let compileResult = compiler.compile(source: expression, fileName: "<eval>")

        switch compileResult {
        case .failure(let diagnostics):
            return .failure(InterpreterError(
                kind: .custom("eval_compile"),
                message: diagnostics.description
            ))
        case .success(let program):
            let evalVM = VM()

            // Copy globals
            for (name, value) in vm.environment.allGlobals() {
                evalVM.environment.setGlobal(name, value: value)
            }

            // Inject in-scope locals as globals so the compiled expression can reference them
            let localVars = inScopeLocals(frameIndex: frameIndex)
            for local in localVars {
                evalVM.environment.setGlobal(local.name, value: local.value)
            }

            // Inject captures as globals
            let captureVars = inScopeCaptures(frameIndex: frameIndex)
            for capture in captureVars {
                evalVM.environment.setGlobal(capture.name, value: capture.cell.value)
            }

            evalVM.load(program)
            evalVM.run()

            switch evalVM.state {
            case .halted:
                if let last = evalVM.stackSnapshot.last {
                    return .success(last)
                }
                return .success(.void)
            case .error(let error):
                return .failure(error)
            default:
                return .success(.void)
            }
        }
    }

    // MARK: - Mutation

    public func setVariable(name: String, value: Value, inFrame frameIndex: Int) -> Result<VariableModification, DebuggerError> {
        guard isPaused else { return .failure(.notPaused) }

        let vmCallStack = vm.callStack
        let basePointer: Int
        let currentOffset: Int

        if vmCallStack.isEmpty {
            guard frameIndex == 0 else { return .failure(.frameIndexOutOfRange(frameIndex)) }
            basePointer = 0
            currentOffset = vm.currentIP
        } else {
            guard frameIndex >= 0 && frameIndex < vmCallStack.count else {
                return .failure(.frameIndexOutOfRange(frameIndex))
            }
            let frame = vmCallStack[frameIndex]
            basePointer = frame.basePointer
            currentOffset = (frameIndex == vmCallStack.count - 1) ? vm.currentIP : frame.ip
        }

        guard let program = loadedProgram else { return .failure(.variableNotFound(name)) }

        // Search variable table for the named variable in scope.
        for record in program.variableTable where record.name == name && record.isInScope(at: currentOffset) {
            let slotIndex = basePointer + Int(record.slotIndex)
            guard slotIndex >= 0 && slotIndex < vm.stack.count else { continue }

            let oldValue = vm.stack[slotIndex]
            vm.setStackValue(value, at: slotIndex)

            let modification = VariableModification(
                name: name,
                oldValue: oldValue,
                newValue: value,
                wasImmutable: !record.isMutable
            )

            let event = DebugEvent.stateModified(
                variable: name,
                oldValue: oldValue,
                newValue: value,
                frameIndex: frameIndex
            )
            logEvent(event)

            return .success(modification)
        }

        // Check globals.
        if let oldValue = vm.environment.getGlobal(name) {
            vm.environment.setGlobal(name, value: value)

            let modification = VariableModification(
                name: name,
                oldValue: oldValue,
                newValue: value,
                wasImmutable: false
            )

            let event = DebugEvent.stateModified(
                variable: name,
                oldValue: oldValue,
                newValue: value,
                frameIndex: frameIndex
            )
            logEvent(event)

            return .success(modification)
        }

        return .failure(.variableNotFound(name))
    }

    public func executeStatement(statement: String, inFrame frameIndex: Int) -> Result<Void, InterpreterError> {
        let compileResult = compiler.compile(source: statement, fileName: "<exec>")

        switch compileResult {
        case .failure(let diagnostics):
            return .failure(InterpreterError(
                kind: .custom("exec_compile"),
                message: diagnostics.description
            ))
        case .success(let program):
            let execVM = VM()

            // Copy globals
            for (name, value) in vm.environment.allGlobals() {
                execVM.environment.setGlobal(name, value: value)
            }

            // Inject in-scope locals as globals
            let localVars = inScopeLocals(frameIndex: frameIndex)
            let localNameSet = Set(localVars.map(\.name))
            for local in localVars {
                execVM.environment.setGlobal(local.name, value: local.value)
            }

            // Inject captures as globals
            let captureVars = inScopeCaptures(frameIndex: frameIndex)
            let captureNameSet = Set(captureVars.map(\.name))
            for capture in captureVars {
                execVM.environment.setGlobal(capture.name, value: capture.cell.value)
            }

            execVM.load(program)
            execVM.run()

            switch execVM.state {
            case .error(let error):
                return .failure(error)
            default:
                // Write back modified values
                for (name, value) in execVM.environment.allGlobals() {
                    if localNameSet.contains(name) {
                        // Write back to the original VM's stack slot
                        if let local = localVars.first(where: { $0.name == name }) {
                            vm.setStackValue(value, at: local.stackIndex)
                        }
                    } else if captureNameSet.contains(name) {
                        // Write back to the capture cell
                        if let capture = captureVars.first(where: { $0.name == name }) {
                            capture.cell.value = value
                        }
                    } else {
                        // Genuine global — write back normally
                        vm.environment.setGlobal(name, value: value)
                    }
                }
                return .success(())
            }
        }
    }

    // MARK: - Event Log

    public var eventLog: [DebugEvent] { _eventLog }

    public func clearEventLog() {
        _eventLog.removeAll()
    }

    // MARK: - Private Helpers

    /// Collect all in-scope local variable names and their stack values for a given frame.
    private func inScopeLocals(frameIndex: Int) -> [(name: String, stackIndex: Int, value: Value)] {
        guard let program = loadedProgram else { return [] }
        let vmCallStack = vm.callStack

        let basePointer: Int
        let currentOffset: Int

        if vmCallStack.isEmpty {
            guard frameIndex == 0 else { return [] }
            basePointer = 0
            currentOffset = vm.currentIP
        } else {
            guard frameIndex >= 0 && frameIndex < vmCallStack.count else { return [] }
            let frame = vmCallStack[frameIndex]
            basePointer = frame.basePointer
            currentOffset = (frameIndex == vmCallStack.count - 1) ? vm.currentIP : frame.ip
        }

        var result: [(name: String, stackIndex: Int, value: Value)] = []
        for record in program.variableTable where record.isInScope(at: currentOffset) {
            let slotIndex = basePointer + Int(record.slotIndex)
            guard slotIndex >= 0 && slotIndex < vm.stack.count else { continue }
            result.append((name: record.name, stackIndex: slotIndex, value: vm.stack[slotIndex]))
        }
        return result
    }

    /// Collect capture cells for a given frame.
    private func inScopeCaptures(frameIndex: Int) -> [(name: String, cell: CaptureCell)] {
        let vmCallStack = vm.callStack
        guard !vmCallStack.isEmpty,
              frameIndex >= 0 && frameIndex < vmCallStack.count,
              let caps = vmCallStack[frameIndex].captures else { return [] }
        return caps.enumerated().map { index, cell in
            (name: "capture_\(index)", cell: cell)
        }
    }

    private func logEvent(_ event: DebugEvent) {
        _eventLog.append(event)
        delegate?.debuggerDidLogEvent(event)
    }

    /// Resolve a line breakpoint to bytecode offsets using the source map.
    private func resolveBreakpoint(_ bp: inout Breakpoint, in program: CompiledProgram) {
        guard case .line(let file, let line) = bp.kind else { return }

        let fileIndex = program.sourceMap.files.firstIndex(of: file).map(UInt16.init) ?? 0

        if let resolved = program.sourceMap.firstExecutableOffset(atOrAfterLine: UInt32(line), fileIndex: fileIndex) {
            bp.resolvedLocation = SourceLocation(fileIndex: fileIndex, line: resolved.line, column: 0)
            bp.resolvedOffsets = Set(program.sourceMap.offsets(forLine: resolved.line, fileIndex: fileIndex))
        }
    }

    /// Patch breakpoint opcodes into the VM.
    private func patchBreakpoint(_ bp: inout Breakpoint) {
        for offset in bp.resolvedOffsets {
            guard offset < vm.currentProgram?.bytecode.count ?? 0 else { continue }
            // Save original opcode if not already saved.
            if bp.originalOpcodes[offset] == nil {
                bp.originalOpcodes[offset] = vm.currentProgram?.bytecode[offset]
            }
        }
    }

    /// Remove breakpoint patches from the VM.
    private func unpatchBreakpoint(_ bp: Breakpoint) {
        for (offset, original) in bp.originalOpcodes {
            vm.originalOpcodes.removeValue(forKey: offset)
            _ = (offset, original)
        }
    }

    /// Rebuild the VM's breakpoint offset set from all enabled breakpoints.
    private func syncBreakpointsToVM() {
        var allOffsets = Set<Int>()
        var allOriginals = [Int: UInt8]()

        for (_, bp) in _breakpoints where bp.isEnabled {
            allOffsets.formUnion(bp.resolvedOffsets)
            for (offset, original) in bp.originalOpcodes {
                allOriginals[offset] = original
            }
        }

        vm.breakpointOffsets = allOffsets
        vm.originalOpcodes = allOriginals
    }

    /// Re-resolve and re-patch all breakpoints after a new program is loaded.
    private func reapplyBreakpoints() {
        guard let program = loadedProgram else { return }
        for id in _breakpoints.keys {
            guard var bp = _breakpoints[id] else { continue }
            bp.resolvedOffsets.removeAll()
            bp.originalOpcodes.removeAll()
            resolveBreakpoint(&bp, in: program)
            patchBreakpoint(&bp)
            _breakpoints[id] = bp
        }
        syncBreakpointsToVM()
    }
}

// MARK: - VMDelegate Conformance

extension Debugger: VMDelegate {
    public func vm(_ vm: VM, didPauseAt location: SourceLocation, reason: PauseReason) {
        // Record breakpoint hit events.
        if case .breakpoint(let ref) = reason {
            if let bp = _breakpoints[ref.id] {
                var updated = bp
                updated.hitCount += 1
                _breakpoints[bp.id] = updated
                logEvent(.breakpointHit(updated, location))
            }
        }

        if case .watchpoint(let variable, let oldValue, let newValue) = reason {
            logEvent(.watchpointTriggered(variable: variable, oldValue: oldValue, newValue: newValue, location: location))
        }

        if case .exception(let error) = reason {
            logEvent(.exceptionRaised(error, location))
        }

        delegate?.debuggerDidPause(at: location, reason: reason)
    }

    public func vmDidResume(_ vm: VM) {
        delegate?.debuggerDidResume()
    }

    public func vm(_ vm: VM, didEncounterError error: InterpreterError) {
        delegate?.debuggerDidEncounterError(error)
    }

    public func vm(_ vm: VM, didProduceOutput text: String) {
        logEvent(.printOutput(text))
        delegate?.debuggerDidProduceOutput(text)
    }

    public func vmDidHalt(_ vm: VM, result: Value?) {
        delegate?.debuggerDidComplete(result: result)
    }
}
