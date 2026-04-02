import Foundation

/// Errors specific to debugger operations.
public enum DebuggerError: Error, Sendable, CustomStringConvertible {
    case notPaused
    case variableNotFound(String)
    case variableOutOfScope(String)
    case typeMismatch(expected: String, got: String)
    case frameIndexOutOfRange(Int)
    case breakpointNotFound(UUID)
    case expressionCompilationFailed(String)

    public var description: String {
        switch self {
        case .notPaused:
            return "Debugger is not paused"
        case .variableNotFound(let name):
            return "Variable '\(name)' not found"
        case .variableOutOfScope(let name):
            return "Variable '\(name)' is out of scope"
        case .typeMismatch(let expected, let got):
            return "Type mismatch: expected \(expected), got \(got)"
        case .frameIndexOutOfRange(let index):
            return "Frame index \(index) out of range"
        case .breakpointNotFound(let id):
            return "Breakpoint \(id) not found"
        case .expressionCompilationFailed(let message):
            return "Expression compilation failed: \(message)"
        }
    }
}
