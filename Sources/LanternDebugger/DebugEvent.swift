import LanternVM

/// An event recorded during a debugging session.
public enum DebugEvent: Sendable {
    case breakpointHit(Breakpoint, SourceLocation)
    case watchpointTriggered(variable: String, oldValue: Value, newValue: Value, location: SourceLocation)
    case exceptionRaised(InterpreterError, SourceLocation)
    case hostCallMade(functionName: String, arguments: [Value], location: SourceLocation)
    case hostCallReturned(functionName: String, result: Value)
    case hostCallThrew(functionName: String, error: String)
    case printOutput(String)
    case stateModified(variable: String, oldValue: Value, newValue: Value, frameIndex: Int)
}
