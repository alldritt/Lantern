import Testing
@testable import LanternCompiler
@testable import LanternVM

@Suite("Token Classification")
struct TokenClassificationTests {
    @Test func classifiesKeywords() {
        let tokens = classifyTokens(source: "let x = 42")
        let keywords = tokens.filter { $0.classification == .keyword }
        #expect(keywords.count >= 1)
        #expect(keywords.first?.text == "let")
    }

    @Test func classifiesIdentifiers() {
        let tokens = classifyTokens(source: "let name = 42")
        let identifiers = tokens.filter { $0.classification == .identifier }
        #expect(identifiers.contains { $0.text == "name" })
    }

    @Test func classifiesNumberLiterals() {
        let tokens = classifyTokens(source: "let x = 42")
        let numbers = tokens.filter { $0.classification == .numberLiteral }
        #expect(numbers.count == 1)
        #expect(numbers.first?.text == "42")
    }

    @Test func classifiesStringLiterals() {
        let tokens = classifyTokens(source: "let s = \"hello\"")
        let strings = tokens.filter { $0.classification == .stringLiteral }
        #expect(!strings.isEmpty)
    }

    @Test func classifiesOperators() {
        let tokens = classifyTokens(source: "let x = 2 + 3")
        let operators = tokens.filter { $0.classification == .operator }
        #expect(operators.contains { $0.text == "+" })
    }

    @Test func classifiesPunctuation() {
        let tokens = classifyTokens(source: "func f(x: Int) { }")
        let punct = tokens.filter { $0.classification == .punctuation }
        #expect(punct.contains { $0.text == "(" })
        #expect(punct.contains { $0.text == ")" })
        #expect(punct.contains { $0.text == "{" })
        #expect(punct.contains { $0.text == "}" })
    }

    @Test func classifiesTypeIdentifiers() {
        let tokens = classifyTokens(source: "let x: String = \"hi\"")
        let types = tokens.filter { $0.classification == .typeIdentifier }
        #expect(types.contains { $0.text == "String" })
    }

    @Test func handlesMultilineSource() {
        let tokens = classifyTokens(source: """
        let a = 1
        let b = 2
        let c = a + b
        """)
        #expect(tokens.count > 5)
        let keywords = tokens.filter { $0.classification == .keyword }
        #expect(keywords.count == 3) // three "let"s
    }

    @Test func includesLocationInfo() {
        let tokens = classifyTokens(source: "let x = 42")
        #expect(tokens.first?.location.line == 1)
    }
}

@Suite("Code Completion")
struct CodeCompletionTests {
    @Test func globalCompletionIncludesKeywords() {
        let items = completions(source: "l", cursorOffset: 1)
        #expect(items.contains { $0.label == "let" })
    }

    @Test func globalCompletionIncludesBuiltinTypes() {
        let items = completions(source: "", cursorOffset: 0)
        #expect(items.contains { $0.label == "String" })
        #expect(items.contains { $0.label == "Int" })
    }

    @Test func globalCompletionIncludesBuiltinFunctions() {
        let items = completions(source: "", cursorOffset: 0)
        #expect(items.contains { $0.label == "print" })
    }

    @Test func dotCompletionIncludesProperties() {
        let items = completions(source: "arr.", cursorOffset: 4)
        #expect(items.contains { $0.label == "count" })
        #expect(items.contains { $0.label == "isEmpty" })
    }

    @Test func bridgeTypesAppearInCompletion() {
        let items = completions(source: "", cursorOffset: 0, bridgeTypes: ["Text", "VStack"])
        #expect(items.contains { $0.label == "Text" })
        #expect(items.contains { $0.label == "VStack" })
    }
}
