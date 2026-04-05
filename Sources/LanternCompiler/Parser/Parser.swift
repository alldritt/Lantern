import LanternVM
import SwiftSyntax
import SwiftParser
import SwiftParserDiagnostics

/// The result of parsing source code.
public struct ParseResult {
    /// The translated AST, if parsing succeeded.
    public let ast: SourceFileNode?
    /// Any diagnostics emitted during parsing.
    public let diagnostics: [CompilerDiagnostic]
    /// The raw SwiftSyntax tree (for IDE tooling).
    public let syntaxTree: SourceFileSyntax

    public init(ast: SourceFileNode?, diagnostics: [CompilerDiagnostic], syntaxTree: SourceFileSyntax) {
        self.ast = ast
        self.diagnostics = diagnostics
        self.syntaxTree = syntaxTree
    }
}

/// Parses Lantern (Swift-subset) source code into an AST.
public struct LanternParser: Sendable {
    public init() {}

    /// Parse source text and return a `ParseResult`.
    public func parse(source: String, fileName: String = "<input>") -> ParseResult {
        let syntaxTree = SwiftParser.Parser.parse(source: source)

        var compilerDiagnostics: [CompilerDiagnostic] = []

        // Use SwiftSyntax's built-in diagnostic generator for comprehensive error detection
        // (missing tokens, unexpected nodes, misplaced syntax, etc.)
        let converter = SourceLocationConverter(fileName: fileName, tree: syntaxTree)
        let parseDiagnostics = ParseDiagnosticsGenerator.diagnostics(for: syntaxTree)
        for diag in parseDiagnostics {
            let loc = diag.location(converter: converter)
            let vmLoc = LanternVM.SourceLocation(
                fileIndex: 0,
                line: UInt32(loc.line),
                column: UInt16(loc.column)
            )
            let severity: DiagnosticSeverity = diag.diagMessage.severity == .error ? .error : .warning
            compilerDiagnostics.append(CompilerDiagnostic(
                message: diag.message,
                location: vmLoc,
                severity: severity
            ))
        }

        // Translate to Lantern AST
        let translator = SyntaxTranslator(fileName: fileName, source: source)
        let ast = translator.translate(syntaxTree)

        // Merge translator diagnostics
        compilerDiagnostics.append(contentsOf: translator.diagnostics)

        return ParseResult(
            ast: ast,
            diagnostics: compilerDiagnostics,
            syntaxTree: syntaxTree
        )
    }
}
