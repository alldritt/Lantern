import LanternVM
import SwiftSyntax
import SwiftParser

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

        // Check for parse errors by walking the tree for unexpected/missing tokens
        let errorCollector = ParseErrorCollector(fileName: fileName, tree: syntaxTree)
        errorCollector.walk(syntaxTree)
        compilerDiagnostics.append(contentsOf: errorCollector.diagnostics)

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

/// Walks the syntax tree to find unexpected or missing tokens that indicate parse errors.
private final class ParseErrorCollector: SyntaxVisitor {
    let converter: SourceLocationConverter
    var diagnostics: [CompilerDiagnostic] = []

    init(fileName: String, tree: SourceFileSyntax) {
        self.converter = SourceLocationConverter(fileName: fileName, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        if token.presence == .missing {
            let loc = token.startLocation(converter: converter)
            let vmLoc = SourceLocation(
                fileIndex: 0,
                line: UInt32(loc.line),
                column: UInt16(loc.column)
            )
            diagnostics.append(CompilerDiagnostic(
                message: "Expected '\(token.tokenKind)'",
                location: vmLoc,
                severity: .error
            ))
        }
        return .visitChildren
    }
}
