/// Protocol for routing print() and debugPrint() output.
public protocol OutputHandler: AnyObject {
    func handlePrint(_ text: String)
    func handleDebugPrint(_ text: String)
}

/// Default handler that writes to stdout.
public final class StandardOutputHandler: OutputHandler {
    public init() {}
    public func handlePrint(_ text: String) { print(text, terminator: "") }
    public func handleDebugPrint(_ text: String) { debugPrint(text, terminator: "") }
}

/// Handler that captures output into arrays for testing and UI display.
public final class CapturedOutputHandler: OutputHandler {
    public private(set) var printOutput: [String] = []
    public private(set) var debugPrintOutput: [String] = []

    public init() {}

    public func handlePrint(_ text: String) { printOutput.append(text) }
    public func handleDebugPrint(_ text: String) { debugPrintOutput.append(text) }

    public func clear() { printOutput.removeAll(); debugPrintOutput.removeAll() }
}
