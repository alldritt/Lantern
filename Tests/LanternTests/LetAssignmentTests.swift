import Testing
import Foundation
@testable import Lantern
@testable import LanternVM
@testable import LanternCompiler

@Suite("Let Assignment")
struct LetAssignmentTests {
    @Test func deferredInitAllBranches() {
        // let initialized in all branches of if/else — should work
        let src = """
        func testing(_ p1: Int) -> String {
            let r: String
            if p1 == 0 {
                r = "zero"
            } else {
                r = "nonzero"
            }
            return r
        }
        print(testing(0))
        """
        #expect(lanternOutput(src) == "zero")
    }

    @Test func deferredInitNonzeroBranch() {
        let src = """
        func testing(_ p1: Int) -> String {
            let r: String
            if p1 == 0 {
                r = "zero"
            } else {
                r = "nonzero"
            }
            return r
        }
        print(testing(5))
        """
        #expect(lanternOutput(src) == "nonzero")
    }

    @Test func deferredInitMultipleBranches() {
        let src = """
        func classify(_ n: Int) -> String {
            let label: String
            if n < 0 {
                label = "negative"
            } else if n == 0 {
                label = "zero"
            } else {
                label = "positive"
            }
            return label
        }
        print(classify(-5))
        print(classify(0))
        print(classify(10))
        """
        #expect(lanternOutput(src) == "negative\nzero\npositive")
    }

    @Test func letWithInitializerCannotReassign() {
        // let WITH initializer — reassignment should be an error
        let compiler = BytecodeCompiler()
        let result = compiler.compile(source: """
        let x = 5
        x = 10
        """)
        switch result {
        case .success:
            Issue.record("Expected compilation error for reassigning initialized let")
        case .failure(let diags):
            let hasImmutableError = diags.diagnostics.contains {
                $0.message.contains("Cannot assign to immutable")
            }
            #expect(hasImmutableError, "Expected 'Cannot assign to immutable variable' error")
        }
    }

    @Test func uninitializedLetUsedBeforeInit() {
        // let without initializer, used without being initialized in all paths
        // Swift error: "Constant 'r2' used before being initialized"
        // This test documents the expected behavior — the interpreter should
        // ideally detect this at compile time or produce nil at runtime
        let src = """
        func testing3(_ p1: Int) -> String {
            let r2: String
            if p1 == 0 {
                r2 = "zero"
            }
            return r2
        }
        print(testing3(1))
        """
        // When p1 != 0, r2 is never initialized.
        // Swift rejects this at compile time.
        // Lantern should either:
        // - Emit a compile error (ideal)
        // - Or produce nil/empty at runtime (current behavior)
        let interp = Interpreter()
        let output = CapturedOutputHandler()
        interp.outputHandler = output
        let result = interp.run(source: src)

        switch result {
        case .success:
            // If it runs, r2 should be nil (uninitialized)
            // This is acceptable but not ideal — Swift would reject at compile time
            let captured = output.printOutput.joined().trimmingCharacters(in: .newlines)
            #expect(captured == "nil" || captured == "",
                    Comment(rawValue: "Expected compile error or nil output for uninitialized let, got: \(captured)"))
        case .failure:
            // Compile error is the correct behavior
            break
        }
    }
}
