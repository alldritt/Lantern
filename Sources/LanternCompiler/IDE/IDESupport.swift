import LanternVM

// MARK: - Token Classification

/// Classification of a source token for syntax highlighting.
public enum TokenClassification: String, Sendable {
    case keyword
    case identifier
    case typeIdentifier
    case numberLiteral
    case stringLiteral
    case comment
    case `operator`
    case punctuation
    case parameter
    case property
    case method
    case enumCase
    case preprocessor
    case placeholder
}

/// Information about a single token in the source.
public struct TokenInfo: Sendable {
    public let text: String
    public let classification: TokenClassification
    public let location: SourceLocation
    public let length: Int

    public init(text: String, classification: TokenClassification, location: SourceLocation, length: Int) {
        self.text = text
        self.classification = classification
        self.location = location
        self.length = length
    }
}

// MARK: - Code Completion

/// The kind of completion item.
public enum CompletionKind: String, Sendable {
    case variable
    case function
    case type
    case property
    case method
    case keyword
    case enumCase
    case snippet
}

/// A single code completion suggestion.
public struct CompletionItem: Sendable {
    public let label: String
    public let kind: CompletionKind
    public let detail: String?
    public let insertText: String
    public let sortPriority: Int

    public init(label: String, kind: CompletionKind, detail: String? = nil, insertText: String? = nil, sortPriority: Int = 0) {
        self.label = label
        self.kind = kind
        self.detail = detail
        self.insertText = insertText ?? label
        self.sortPriority = sortPriority
    }
}
