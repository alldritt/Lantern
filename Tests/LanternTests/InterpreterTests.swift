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
}
