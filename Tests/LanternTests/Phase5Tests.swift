import Testing
import Foundation
@testable import Lantern

@Suite("Phase 5 — Arrays")
struct Phase5ArrayTests {
    @Test func array_literal() { #expect(lanternOutput("let a = [1, 2, 3]\nprint(a)") == "[1, 2, 3]") }
    @Test func array_empty() { #expect(lanternOutput("let a: [Int] = []\nprint(a)") == "[]") }
    @Test func array_subscript_read() { #expect(lanternOutput("let a = [10, 20, 30]\nprint(a[1])") == "20") }
    @Test func array_count() { #expect(lanternOutput("let a = [1, 2, 3]\nprint(a.count)") == "3") }
    @Test func array_isEmpty_false() { #expect(lanternOutput("let a = [1]\nprint(a.isEmpty)") == "false") }
    @Test func array_isEmpty_true() { #expect(lanternOutput("let a: [Int] = []\nprint(a.isEmpty)") == "true") }

    @Test func for_in_array() {
        let src = """
        let names = ["Alice", "Bob", "Charlie"]
        for name in names {
            print(name)
        }
        """
        #expect(lanternOutput(src) == "Alice\nBob\nCharlie")
    }

    @Test func array_append() {
        let src = """
        var a = [1, 2]
        a.append(3)
        print(a)
        """
        #expect(lanternOutput(src) == "[1, 2, 3]")
    }

    @Test func array_in_function() {
        let src = """
        func sum(arr: [Int]) -> Int {
            var total = 0
            for x in arr {
                total += x
            }
            return total
        }
        print(sum(arr: [1, 2, 3, 4, 5]))
        """
        #expect(lanternOutput(src) == "15")
    }
}

@Suite("Phase 5 — Dictionaries")
struct Phase5DictTests {
    @Test func dict_literal() {
        let src = "let d = [\"a\": 1, \"b\": 2]\nprint(d[\"a\"]!)"
        #expect(lanternOutput(src) == "1")
    }

    @Test func dict_subscript_missing() {
        let src = "let d = [\"a\": 1]\nlet v = d[\"b\"]\nif v == nil { print(\"nil\") }"
        #expect(lanternOutput(src) == "nil")
    }
}

@Suite("Phase 5 — Optionals")
struct Phase5OptionalTests {
    @Test func nil_coalescing() {
        let src = """
        let x: Int? = nil
        print(x ?? 42)
        """
        #expect(lanternOutput(src) == "42")
    }

    @Test func optional_some() {
        let src = """
        let x: Int? = 10
        print(x ?? 0)
        """
        #expect(lanternOutput(src) == "10")
    }

    @Test func if_let() {
        let src = """
        let x: Int? = 5
        if let val = x {
            print(val)
        } else {
            print("nil")
        }
        """
        #expect(lanternOutput(src) == "5")
    }

    @Test func if_let_nil() {
        let src = """
        let x: Int? = nil
        if let val = x {
            print(val)
        } else {
            print("nil")
        }
        """
        #expect(lanternOutput(src) == "nil")
    }
}
