import LanternVM

/// Severity level for compiler diagnostics.
public enum DiagnosticSeverity: String, Sendable {
    case error
    case warning
    case note
}

/// A single diagnostic emitted during compilation.
public struct CompilerDiagnostic: Sendable, CustomStringConvertible {
    public let message: String
    public let location: SourceLocation?
    public let severity: DiagnosticSeverity
    public let sourceLine: String?

    public init(message: String, location: SourceLocation? = nil, severity: DiagnosticSeverity = .error, sourceLine: String? = nil) {
        self.message = message
        self.location = location
        self.severity = severity
        self.sourceLine = sourceLine
    }

    public var description: String {
        var result = "\(severity.rawValue)"
        if let loc = location {
            result += " at \(loc)"
        }
        result += ": \(message)"
        if let line = sourceLine {
            result += "\n  | \(line)"
        }
        return result
    }
}

/// A collection of diagnostics that conforms to `Error` for use as a failure type.
public struct CompilerDiagnostics: Error, Sendable, CustomStringConvertible {
    public var diagnostics: [CompilerDiagnostic]

    public init(diagnostics: [CompilerDiagnostic] = []) {
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }

    public var errors: [CompilerDiagnostic] {
        diagnostics.filter { $0.severity == .error }
    }

    public var warnings: [CompilerDiagnostic] {
        diagnostics.filter { $0.severity == .warning }
    }

    public var description: String {
        diagnostics.map(\.description).joined(separator: "\n")
    }
}
