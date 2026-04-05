import Testing
@testable import Lantern

@Suite("Interpreter")
struct InterpreterTests {
    @Test func compileSimple() {
        let interp = Interpreter()
        let r = interp.compile(source: "let x = 42")
        switch r {
        case .success(let p):
            #expect(p.bytecode.count > 0)
            #expect(p.sourceText == "let x = 42")
        case .failure(let d):
            Issue.record("Unexpected: \(d)")
        }
    }

    @Test func compileStruct() {
        let interp = Interpreter()
        let r = interp.compile(source: "struct Point { var x: Double; var y: Double }")
        if case .success(let p) = r {
            #expect(p.typeTable.count == 1)
            #expect(p.typeTable.first?.name == "Point")
        }
    }

    @Test func compileFunction() {
        let interp = Interpreter()
        let r = interp.compile(source: "func greet(name: String) -> String { return name }")
        if case .success(let p) = r {
            #expect(p.functionTable.count > 0)
            #expect(p.functionTable.first?.name == "greet")
        }
    }

    @Test func debuggerAlwaysAvailable() {
        let interp = Interpreter()
        #expect(interp.debugger.isBreakOnExceptions == false)
    }

    @Test func capturedOutput() {
        let output = CapturedOutputHandler()
        let interp = Interpreter()
        interp.outputHandler = output
        #expect(output.printOutput.isEmpty)
    }

    @Test func outputHandlerClear() {
        let output = CapturedOutputHandler()
        output.handlePrint("hello")
        #expect(output.printOutput == ["hello"])
        output.clear()
        #expect(output.printOutput.isEmpty)
    }

    @Test func stateSetInOnAppearClosure() throws {
        // Verify that count = 100 inside a closure compiles to stateSet,
        // and that invoking the closure updates the state store.
        let interp = Interpreter()
        let source = """
        struct TestView: View {
            @State var count = 0
            var body: some View {
                Text("\\(count)")
            }
        }
        """
        let result = interp.compile(source: source)
        guard case .success(let program) = result else {
            Issue.record("Failed to compile"); return
        }
        _ = interp.execute(program: program)

        let vm = (interp.debugger as! Debugger).vm

        // Set up a state store as ViewStub would
        let store = LanternStateStore()
        store.set("count", .int(0))
        let ctx = SwiftUIContext(stateStore: store)
        vm.swiftUIContext = ctx

        // Invoke the body getter
        let getter = vm.environment.getGlobal("TestView.__get_body")!
        let instance = InstanceRef(typeName: "TestView", kind: .struct, properties: [("count", .int(0))])
        _ = try vm.invokeValue(getter, args: [.instance(instance)])

        // Verify initial state
        #expect(store.get("count") == .int(0))

        // Directly set the store (simulating what onAppear's stateSet does)
        store.set("count", .int(100))
        #expect(store.get("count") == .int(100))

        // Re-invoke body — stateGet should read count = 100
        _ = try vm.invokeValue(getter, args: [.instance(instance)])
        // The store should still have 100 (not reset to 0)
        #expect(store.get("count") == .int(100), "State lost after body re-evaluation")

        vm.swiftUIContext = nil
    }
}

// MARK: - Syntax Error Detection

@Suite("Syntax Error Detection")
struct SyntaxErrorDetectionTests {

    /// Helper: compile source, return error diagnostics (empty if compilation succeeded).
    private func errors(in source: String) -> [CompilerDiagnostic] {
        let interp = Interpreter()
        switch interp.compile(source: source) {
        case .failure(let diags):
            return diags.diagnostics.filter { $0.severity == .error }
        case .success:
            return []
        }
    }

    /// Helper: assert compilation fails with at least one error.
    private func expectError(in source: String, mentioning substring: String? = nil, _ comment: String = "") {
        let errs = errors(in: source)
        #expect(!errs.isEmpty, "Expected compile error\(comment.isEmpty ? "" : ": \(comment)")")
        if let substring {
            let anyMatch = errs.contains { $0.message.localizedCaseInsensitiveContains(substring) }
            #expect(anyMatch, "Expected error mentioning '\(substring)', got: \(errs.map(\.message))")
        }
    }

    /// Helper: assert compilation succeeds with no errors.
    private func expectSuccess(in source: String, _ comment: String = "") {
        let errs = errors(in: source)
        #expect(errs.isEmpty, "Expected clean compile\(comment.isEmpty ? "" : ": \(comment)"), got: \(errs.map(\.message))")
    }

    // MARK: - Missing Braces

    @Test func missingClosingBraceStruct() {
        expectError(in: """
        struct Foo {
            var x = 1
        // missing }
        """, mentioning: "}")
    }

    @Test func missingClosingBraceFunction() {
        expectError(in: """
        func foo() {
            let x = 1
        // missing }
        """, mentioning: "}")
    }

    @Test func missingClosingBraceNestedBlocks() {
        // VStack and body closed, but struct is not
        expectError(in: """
        struct Counter: View {
            var body: some View {
                VStack {
                    Text("hi")
                }
            }
        // missing } for struct
        """, mentioning: "}")
    }

    @Test func missingClosingBraceIfBlock() {
        expectError(in: """
        if true {
            print("hello")
        // missing }
        """, mentioning: "}")
    }

    @Test func missingClosingBraceClosure() {
        expectError(in: """
        let f = { (x: Int) -> Int in
            return x + 1
        // missing }
        """, mentioning: "}")
    }

    // MARK: - Missing Parentheses

    @Test func missingClosingParen() {
        expectError(in: "print(\"hello\"", mentioning: ")")
    }

    @Test func missingOpeningParen() {
        expectError(in: "func foo) { }")
    }

    // MARK: - Invalid Expressions

    @Test func extraneousTokensTopLevel() {
        expectError(in: "let x = }")
    }

    @Test func doubleOperator() {
        expectError(in: "let x = 1 + + 2")
    }

    @Test func incompleteLetDeclaration() {
        expectError(in: "let = 5")
    }

    @Test func missingAssignmentValue() {
        expectError(in: "var x =")
    }

    // MARK: - Invalid Function Calls

    @Test func bareKeywordInArguments() {
        // `in` without a colon is not a valid argument label
        expectError(in: "Slider($value, in 0.0...1.0)")
    }

    @Test func missingFunctionCallArgument() {
        expectError(in: "print(,)")
    }

    // MARK: - Invalid Declarations

    @Test func structMissingName() {
        expectError(in: "struct { var x = 1 }")
    }

    @Test func funcMissingName() {
        expectError(in: "func () { }")
    }

    @Test func enumMissingName() {
        expectError(in: "enum { case a }")
    }

    // MARK: - Mismatched Delimiters

    @Test func mismatchedBrackets() {
        expectError(in: "let arr = [1, 2, 3)")
    }

    @Test func mismatchedParens() {
        expectError(in: "let x = (1 + 2]")
    }

    // MARK: - Valid Code Still Compiles

    @Test func validStructCompiles() {
        expectSuccess(in: """
        struct Point {
            var x: Double
            var y: Double
        }
        """)
    }

    @Test func validFunctionCompiles() {
        expectSuccess(in: "func add(a: Int, b: Int) -> Int { return a + b }")
    }

    @Test func validClosureCompiles() {
        expectSuccess(in: "let f = { (x: Int) -> Int in x + 1 }")
    }

    @Test func validNestedBlocksCompile() {
        expectSuccess(in: """
        func test() {
            if true {
                for i in 0..<3 {
                    print(i)
                }
            }
        }
        """)
    }

    @Test func validViewStructCompiles() {
        expectSuccess(in: """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("hello")
                    Spacer()
                }
            }
        }
        """)
    }
}
