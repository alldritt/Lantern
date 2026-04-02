import LanternVM

/// Collects diagnostics during compilation.
public final class DiagnosticEngine: @unchecked Sendable {
    private var collected: [CompilerDiagnostic] = []
    private var sourceLines: [String] = []
    private var fileName: String = "<input>"

    public init() {}

    /// Configure the engine with source text for source-line extraction.
    public func setSource(_ source: String, fileName: String) {
        self.sourceLines = source.components(separatedBy: "\n")
        self.fileName = fileName
    }

    // MARK: - Emit

    public func emit(_ message: String, at location: SourceLocation? = nil, severity: DiagnosticSeverity = .error) {
        let line = extractSourceLine(at: location)
        let diagnostic = CompilerDiagnostic(message: message, location: location, severity: severity, sourceLine: line)
        collected.append(diagnostic)
    }

    public func error(_ message: String, at location: SourceLocation? = nil) {
        emit(message, at: location, severity: .error)
    }

    public func warning(_ message: String, at location: SourceLocation? = nil) {
        emit(message, at: location, severity: .warning)
    }

    public func note(_ message: String, at location: SourceLocation? = nil) {
        emit(message, at: location, severity: .note)
    }

    // MARK: - Query

    public var hasErrors: Bool {
        collected.contains { $0.severity == .error }
    }

    public var diagnostics: [CompilerDiagnostic] { collected }

    public func toDiagnostics() -> CompilerDiagnostics {
        CompilerDiagnostics(diagnostics: collected)
    }

    public func reset() {
        collected.removeAll()
    }

    // MARK: - Private

    private func extractSourceLine(at location: SourceLocation?) -> String? {
        guard let loc = location else { return nil }
        let lineIndex = Int(loc.line) - 1
        guard lineIndex >= 0, lineIndex < sourceLines.count else { return nil }
        return sourceLines[lineIndex]
    }
}
