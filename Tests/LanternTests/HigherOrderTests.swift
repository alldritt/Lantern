import Testing
import Foundation
@testable import Lantern

@Suite("Higher Order")
struct HigherOrderTests {
    @Test func reduceSum() {
        #expect(lanternOutput("print([1, 2, 3, 4, 5].reduce(0) { $0 + $1 })") == "15")
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
