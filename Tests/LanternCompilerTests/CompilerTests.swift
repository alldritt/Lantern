import Testing
@testable import LanternVM
@testable import LanternCompiler

@Suite("Parser")
struct ParserTests {
    @Test func parseInt() {
        let r = LanternParser().parse(source: "42")
        #expect(r.ast != nil); #expect(r.ast?.statements.count == 1)
    }
    @Test func parseLet() { #expect(LanternParser().parse(source: "let x = 42").ast != nil) }
    @Test func parseVar() { #expect(LanternParser().parse(source: "var x = 42").ast != nil) }
    @Test func parseBinary() { #expect(LanternParser().parse(source: "2 + 3").ast != nil) }
    @Test func parseFunc() { #expect(LanternParser().parse(source: "func f(a: Int) -> Int { return a }").ast != nil) }
    @Test func parseIf() { #expect(LanternParser().parse(source: "if true { let x = 1 } else { let y = 2 }").ast != nil) }
    @Test func parseFor() { #expect(LanternParser().parse(source: "for i in 0..<10 { print(i) }").ast != nil) }
    @Test func parseStruct() { #expect(LanternParser().parse(source: "struct P { var x: Double; var y: Double }").ast != nil) }
}

@Suite("Compiler")
struct CompilerTests {
    @Test func compileExpression() {
        let r = BytecodeCompiler().compile(source: "let x = 2 + 3")
        switch r {
        case .success(let p): #expect(p.bytecode.count > 0)
        case .failure(let d): Issue.record("Unexpected: \(d)")
        }
    }
    @Test func compiledProgramHasSourceText() {
        let r = BytecodeCompiler().compile(source: "let x = 1", fileName: "test.swift")
        if case .success(let p) = r {
            #expect(p.sourceText == "let x = 1")
            #expect(p.fileName == "test.swift")
        }
    }
    @Test func compileFunction() {
        let r = BytecodeCompiler().compile(source: "func greet(name: String) -> String { return name }")
        if case .success(let p) = r { #expect(p.functionTable.count > 0) }
    }
}

@Suite("Optimizer")
struct OptimizerTests {
    private func firstVarInit(_ ast: ASTNode) -> ExpressionNode? {
        guard let f = ast as? SourceFileNode, let v = f.statements.first as? VariableDeclarationNode else { return nil }
        return v.initializer
    }
    private func fold(_ src: String) throws -> ASTNode {
        let r = LanternParser().parse(source: src)
        guard let ast = r.ast else { return SourceFileNode(fileName: "", statements: []) }
        let ctx = OptimizationContext()
        return try ConstantFoldingPass().run(ast, context: ctx)
    }

    @Test func foldIntAdd() throws { #expect((firstVarInit(try fold("let x = 2 + 3")) as? IntLiteralNode)?.value == 5) }
    @Test func foldIntMul() throws { #expect((firstVarInit(try fold("let x = 4 * 5")) as? IntLiteralNode)?.value == 20) }
    @Test func foldStringConcat() throws { #expect((firstVarInit(try fold(#"let x = "a" + "b""#)) as? StringLiteralNode)?.value == "ab") }
    @Test func foldNot() throws { #expect((firstVarInit(try fold("let x = !true")) as? BoolLiteralNode)?.value == false) }
    @Test func foldNeg() throws { #expect((firstVarInit(try fold("let x = -5")) as? IntLiteralNode)?.value == -5) }
    @Test func noFoldVariable() throws { #expect(firstVarInit(try fold("let x = a + 3")) is BinaryExpressionNode) }

    @Test func fullPipeline() throws {
        let r = LanternParser().parse(source: "let x = 2 + 3")
        guard let ast = r.ast else { Issue.record("No AST"); return }
        let opt = try Optimizer().optimize(ast)
        #expect((firstVarInit(opt) as? IntLiteralNode)?.value == 5)
    }
}
