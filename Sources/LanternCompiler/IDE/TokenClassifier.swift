import SwiftSyntax
import SwiftParser
import LanternVM

/// Classify all tokens in Swift source for syntax highlighting.
/// Uses SwiftSyntax to parse and walk the token tree.
public func classifyTokens(source: String, fileName: String = "<input>") -> [TokenInfo] {
    let sourceFile = Parser.parse(source: source)
    var tokens: [TokenInfo] = []

    for token in sourceFile.tokens(viewMode: .sourceAccurate) {
        let text = token.text
        if text.isEmpty { continue }

        let classification = classify(token: token)
        let position = token.positionAfterSkippingLeadingTrivia
        let converter = SourceLocationConverter(fileName: fileName, tree: sourceFile)
        let loc = converter.location(for: position)

        tokens.append(TokenInfo(
            text: text,
            classification: classification,
            location: LanternVM.SourceLocation(
                fileIndex: 0,
                line: UInt32(loc.line),
                column: UInt16(loc.column)
            ),
            length: text.count
        ))
    }

    return tokens
}

// MARK: - Token Classification Logic

private func classify(token: TokenSyntax) -> TokenClassification {
    switch token.tokenKind {
    // Keywords
    case .keyword:
        return .keyword

    // Literals
    case .integerLiteral, .floatLiteral:
        return .numberLiteral
    case .stringSegment, .stringQuote, .multilineStringQuote, .rawStringPoundDelimiter:
        return .stringLiteral

    // Identifiers
    case .identifier(let name):
        // Heuristic: uppercase first letter → type identifier
        if let first = name.first, first.isUppercase {
            return .typeIdentifier
        }
        // Check parent context for more specific classification
        if let parent = token.parent {
            if parent.is(FunctionDeclSyntax.self) || parent.is(FunctionCallExprSyntax.self) {
                return .method
            }
        }
        return .identifier

    // Operators
    case .binaryOperator, .prefixOperator, .postfixOperator:
        return .operator
    case .equal, .arrow, .period, .colon, .ellipsis:
        return .operator

    // Punctuation
    case .leftParen, .rightParen, .leftBrace, .rightBrace,
         .leftSquare, .rightSquare, .comma, .semicolon:
        return .punctuation

    // Comments handled via trivia, not tokens — but just in case
    case .endOfFile:
        return .punctuation

    // String interpolation anchors
    case .backslash:
        return .stringLiteral

    // At-sign for attributes
    case .atSign:
        return .preprocessor

    // Pound keywords
    case .poundAvailable, .poundUnavailable, .poundSourceLocation:
        return .preprocessor

    default:
        return .identifier
    }
}

