import Testing
import Foundation
@testable import Lantern

@Suite("Higher Order")
struct HigherOrderTests {
    @Test func reduceSum() {
        #expect(lanternOutput("print([1, 2, 3, 4, 5].reduce(0) { $0 + $1 })") == "15")
    }

    @Test func reduceSimpleConcat() {
        // Simpler reduce test first
        #expect(lanternOutput(#"print(["a", "b", "c"].reduce("") { $0 + $1 })"#) == "abc")
    }

    @Test func ternaryInClosure() {
        // Simple ternary in closure
        #expect(lanternOutput(#"print([1, 2, 3].map { $0 > 1 ? "big" : "small" })"#) == #"["small", "big", "big"]"#)
    }

    @Test func reduceString() {
        let src = """
        let joined = ["a", "b", "c"].reduce("") { result, item in
            result.isEmpty ? item : result + "-" + item
        }
        print(joined)
        """
        #expect(lanternOutput(src) == "a-b-c")
    }

    @Test func mapFilter() {
        let src = """
        let result = [1, 2, 3, 4, 5]
            .filter { $0 % 2 != 0 }
            .map { $0 * $0 }
        print(result)
        """
        #expect(lanternOutput(src) == "[1, 9, 25]")
    }

    @Test func closureCapture() {
        let src = """
        func makeMultiplier(_ factor: Int) -> (Int) -> Int {
            return { n in n * factor }
        }
        let triple = makeMultiplier(3)
        print(triple(10))
        """
        #expect(lanternOutput(src) == "30")
    }

    @Test func staticMethod() {
        let src = """
        struct MathHelper {
            static func square(_ n: Int) -> Int {
                return n * n
            }
        }
        print(MathHelper.square(5))
        """
        #expect(lanternOutput(src) == "25")
    }
}
