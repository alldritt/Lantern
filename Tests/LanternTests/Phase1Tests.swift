import Testing
import Foundation
@testable import Lantern
@testable import LanternVM

/// Run a source string through the interpreter and return captured output.
func lanternOutput(_ source: String) -> String {
    let interp = Interpreter()
    let output = CapturedOutputHandler()
    interp.outputHandler = output
    _ = interp.run(source: source)
    return output.printOutput.joined().trimmingCharacters(in: .newlines)
}

@Suite("Phase 1 — Arithmetic")
struct Phase1ArithmeticTests {
    @Test func add_integers() { #expect(lanternOutput("print(3 + 4)") == "7") }
    @Test func add_doubles() { #expect(lanternOutput("print(2.5 + 3.0)") == "5.5") }
    @Test func subtract_integers() { #expect(lanternOutput("print(10 - 4)") == "6") }
    @Test func subtract_doubles() { #expect(lanternOutput("print(4.0 - 2.5)") == "1.5") }
    @Test func multiply_integers() { #expect(lanternOutput("print(6 * 4)") == "24") }
    @Test func multiply_doubles() { #expect(lanternOutput("print(2.5 * 3.0)") == "7.5") }
    @Test func divide_integers() { #expect(lanternOutput("print(15 / 5)") == "3") }
    @Test func integer_division_truncates() { #expect(lanternOutput("print(10 / 3)") == "3") }
    @Test func divide_doubles() { #expect(lanternOutput("print(5.0 / 2.0)") == "2.5") }
    @Test func modulo() { #expect(lanternOutput("print(10 % 3)") == "1") }
    @Test func modulo_no_remainder() { #expect(lanternOutput("print(9 % 3)") == "0") }
    @Test func negate_integer() { #expect(lanternOutput("print(-5)") == "-5") }
    @Test func negate_double() { #expect(lanternOutput("print(-3.14)") == "-3.14") }
    @Test func large_integer() { #expect(lanternOutput("print(1000000 * 1000)") == "1000000000") }

    // Multi-statement tests
    @Test func double_negation() {
        #expect(lanternOutput("let x = 5\nprint(-(-x))") == "5")
    }
    @Test func complex_expression() {
        #expect(lanternOutput("let a = 10\nlet b = 3\nlet c = 4\nprint(a * c + b - 1)") == "42")
    }
    @Test func compound_add() {
        #expect(lanternOutput("var total = 10\ntotal += 5\nprint(total)") == "15")
    }
}

@Suite("Phase 1 — Strings")
struct Phase1StringTests {
    @Test func string_literal() { #expect(lanternOutput(#"print("Hello")"#) == "Hello") }
    @Test func string_concat() { #expect(lanternOutput(#"print("Hello" + " " + "World")"#) == "Hello World") }
    @Test func string_variable() { #expect(lanternOutput("let s = \"Hello\"\nprint(s)") == "Hello") }
}
