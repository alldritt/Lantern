/// Runtime errors raised during VM execution.
public struct InterpreterError: Error, Sendable, CustomStringConvertible {
    public let kind: ErrorKind
    public let message: String
    public let location: SourceLocation?
    public let sourceLine: String?

    public init(kind: ErrorKind, message: String, location: SourceLocation? = nil, sourceLine: String? = nil) {
        self.kind = kind
        self.message = message
        self.location = location
        self.sourceLine = sourceLine
    }

    public var description: String {
        if let loc = location {
            return "Runtime error at \(loc): \(message)"
        }
        return "Runtime error: \(message)"
    }
}

public enum ErrorKind: Sendable, Equatable {
    case typeMismatch
    case nilUnwrap
    case indexOutOfBounds
    case divisionByZero
    case stackOverflow
    case undefinedVariable
    case undefinedFunction
    case undefinedMethod
    case undefinedProperty
    case wrongArgumentCount
    case argumentLabelMismatch
    case immutableAssignment
    case missingReturn
    case uncaughtThrow
    case hostBridgeError
    case executionLimitExceeded
    case custom(String)
}

// Convenience factories
extension InterpreterError {
    public static func typeMismatch(_ msg: String, at loc: SourceLocation? = nil) -> Self {
        .init(kind: .typeMismatch, message: msg, location: loc)
    }
    public static func divisionByZero(at loc: SourceLocation? = nil) -> Self {
        .init(kind: .divisionByZero, message: "Division by zero", location: loc)
    }
    public static func nilUnwrap(at loc: SourceLocation? = nil) -> Self {
        .init(kind: .nilUnwrap, message: "Unexpectedly found nil while unwrapping an Optional value", location: loc)
    }
    public static func indexOutOfBounds(_ index: Int, count: Int, at loc: SourceLocation? = nil) -> Self {
        .init(kind: .indexOutOfBounds, message: "Index \(index) out of range (count: \(count))", location: loc)
    }
    public static func stackOverflow(at loc: SourceLocation? = nil) -> Self {
        .init(kind: .stackOverflow, message: "Stack overflow", location: loc)
    }
    public static func undefinedVariable(_ name: String, at loc: SourceLocation? = nil) -> Self {
        .init(kind: .undefinedVariable, message: "Undefined variable '\(name)'", location: loc)
    }
    public static func undefinedFunction(_ name: String, at loc: SourceLocation? = nil) -> Self {
        .init(kind: .undefinedFunction, message: "Undefined function '\(name)'", location: loc)
    }
    public static func undefinedMethod(_ name: String, on type: String, at loc: SourceLocation? = nil) -> Self {
        .init(kind: .undefinedMethod, message: "Value of type '\(type)' has no member '\(name)'", location: loc)
    }
    public static func undefinedProperty(_ name: String, on type: String, at loc: SourceLocation? = nil) -> Self {
        .init(kind: .undefinedProperty, message: "Value of type '\(type)' has no property '\(name)'", location: loc)
    }
    public static func wrongArgumentCount(expected: Int, got: Int, at loc: SourceLocation? = nil) -> Self {
        .init(kind: .wrongArgumentCount, message: "Expected \(expected) arguments, got \(got)", location: loc)
    }
    public static func executionLimitExceeded(at loc: SourceLocation? = nil) -> Self {
        .init(kind: .executionLimitExceeded, message: "Execution step limit exceeded", location: loc)
    }
    public static func notCallable(_ type: String, at loc: SourceLocation? = nil) -> Self {
        .init(kind: .typeMismatch, message: "Value of type '\(type)' is not callable", location: loc)
    }
    public static func thrownError(_ value: Value, at loc: SourceLocation? = nil) -> Self {
        .init(kind: .uncaughtThrow, message: "Thrown error: \(value.debugSummary)", location: loc)
    }
}
