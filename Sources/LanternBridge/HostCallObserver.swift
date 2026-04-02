import LanternVM

/// Observer protocol for monitoring host-side calls from the interpreter.
public protocol HostCallObserver: AnyObject {
    func willCallHost(functionName: String, arguments: [Value], location: SourceLocation?)
    func didReturnFromHost(functionName: String, result: Value)
    func didThrowFromHost(functionName: String, error: Error)
}
