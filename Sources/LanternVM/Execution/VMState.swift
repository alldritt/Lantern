import Foundation

/// The execution state of the virtual machine.
public enum ExecutionState: Sendable {
    case ready
    case running
    case paused(PauseReason)
    case halted
    case error(InterpreterError)
}

/// Why the VM paused.
public indirect enum PauseReason: Sendable {
    case breakpoint(BreakpointRef)
    case step
    case watchpoint(variable: String, oldValue: Value, newValue: Value)
    case exception(InterpreterError)
    case userRequested
}

/// Lightweight reference to a breakpoint (VM-side, no dependency on Debugger).
public struct BreakpointRef: Sendable {
    public let id: UUID
    public let location: SourceLocation

    public init(id: UUID = UUID(), location: SourceLocation) {
        self.id = id; self.location = location
    }
}
