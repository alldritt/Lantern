import LanternVM

/// Receives notifications about debugger state changes.
public protocol DebuggerDelegate: AnyObject {
    func debuggerDidPause(at location: SourceLocation, reason: PauseReason)
    func debuggerDidResume()
    func debuggerDidEncounterError(_ error: InterpreterError)
    func debuggerDidProduceOutput(_ text: String)
    func debuggerDidLogEvent(_ event: DebugEvent)
    func debuggerDidComplete(result: Value?)
}

// Default empty implementations so all methods are optional for adopters.
extension DebuggerDelegate {
    public func debuggerDidPause(at location: SourceLocation, reason: PauseReason) {}
    public func debuggerDidResume() {}
    public func debuggerDidEncounterError(_ error: InterpreterError) {}
    public func debuggerDidProduceOutput(_ text: String) {}
    public func debuggerDidLogEvent(_ event: DebugEvent) {}
    public func debuggerDidComplete(result: Value?) {}
}
