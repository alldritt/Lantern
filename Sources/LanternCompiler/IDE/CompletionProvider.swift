import SwiftSyntax
import SwiftParser
import LanternVM

/// Provide code completion suggestions at a cursor position.
/// Combines scope-local variables, type members, and bridge-registered types.
public func completions(
    source: String,
    cursorOffset: Int,
    compiler: BytecodeCompiler? = nil,
    bridgeTypes: [String] = [],
    bridgeMethods: [String: [String]] = [:]
) -> [CompletionItem] {
    var items: [CompletionItem] = []

    // Parse the source to get context
    let sourceFile = Parser.parse(source: source)

    // Determine what's before the cursor
    let prefix = String(source.prefix(cursorOffset))
    let lastLine = prefix.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
    let trimmed = lastLine.trimmingCharacters(in: .whitespaces)

    // After a dot: member completion
    if trimmed.hasSuffix(".") {
        // Extract the receiver identifier
        let beforeDot = String(trimmed.dropLast())
        let receiverName = beforeDot.split(separator: " ").last.map(String.init) ?? ""

        // Check for known type methods
        if let methods = bridgeMethods[receiverName] {
            for method in methods {
                items.append(CompletionItem(label: method, kind: .method, detail: "\(receiverName).\(method)"))
            }
        }

        // Add common modifiers for view types
        if bridgeTypes.contains(receiverName) || ["Text", "VStack", "HStack", "Button", "Image"].contains(receiverName) {
            for mod in viewModifiers {
                items.append(CompletionItem(label: mod, kind: .method, detail: "View modifier"))
            }
        }

        // Add common properties
        items.append(CompletionItem(label: "count", kind: .property, detail: "Int"))
        items.append(CompletionItem(label: "isEmpty", kind: .property, detail: "Bool"))

        return items.sorted { $0.label < $1.label }
    }

    // At start of line or after whitespace: global completion
    // Keywords
    for kw in swiftKeywords {
        if kw.hasPrefix(trimmed) || trimmed.isEmpty {
            items.append(CompletionItem(label: kw, kind: .keyword, sortPriority: 10))
        }
    }

    // Bridge-registered types
    for typeName in bridgeTypes {
        items.append(CompletionItem(label: typeName, kind: .type, detail: "Bridge type", sortPriority: 5))
    }

    // Built-in types
    for typeName in ["Int", "Double", "String", "Bool", "Array", "Dictionary", "Optional"] {
        items.append(CompletionItem(label: typeName, kind: .type, sortPriority: 8))
    }

    // Built-in functions
    for fn in ["print", "abs", "min", "max", "zip", "type"] {
        items.append(CompletionItem(label: fn, kind: .function, sortPriority: 7))
    }

    // Collect identifiers already declared in the source
    for token in sourceFile.tokens(viewMode: .sourceAccurate) {
        if case .identifier(let name) = token.tokenKind {
            // Check if it's a declaration
            if let parent = token.parent,
               (parent.is(PatternBindingSyntax.self) || parent.is(FunctionDeclSyntax.self) ||
                parent.is(StructDeclSyntax.self) || parent.is(ClassDeclSyntax.self)) {
                if !items.contains(where: { $0.label == name }) {
                    items.append(CompletionItem(label: name, kind: .variable, sortPriority: 3))
                }
            }
        }
    }

    return items.sorted { $0.sortPriority < $1.sortPriority }
}

// MARK: - Constants

private let swiftKeywords = [
    "let", "var", "func", "struct", "class", "enum", "protocol", "extension",
    "if", "else", "guard", "for", "in", "while", "switch", "case", "default",
    "return", "break", "continue", "defer", "do", "try", "catch", "throw",
    "import", "true", "false", "nil", "self", "static", "mutating",
    "print", "@State", "@Binding", "@Published"
]

private let viewModifiers = [
    "padding", "frame", "font", "bold", "italic",
    "foregroundColor", "foregroundStyle", "background",
    "opacity", "cornerRadius", "shadow", "border",
    "hidden", "disabled", "navigationTitle",
    "onAppear", "onDisappear", "onTapGesture",
    "sheet", "alert"
]
