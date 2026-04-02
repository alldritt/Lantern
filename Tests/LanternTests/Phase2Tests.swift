import Testing
import Foundation
@testable import Lantern

@Suite("Phase 2 — Control Flow")
struct Phase2Tests {
    @Test func if_true() {
        #expect(lanternOutput("if true { print(1) }") == "1")
    }
    @Test func if_false() {
        #expect(lanternOutput("if false { print(1) }") == "")
    }
    @Test func if_else_true() {
        #expect(lanternOutput("if true { print(1) } else { print(2) }") == "1")
    }
    @Test func if_else_false() {
        #expect(lanternOutput("if false { print(1) } else { print(2) }") == "2")
    }
    @Test func if_comparison() {
        #expect(lanternOutput("let x = 10\nif x > 5 { print(\"big\") } else { print(\"small\") }") == "big")
    }
    @Test func while_loop() {
        #expect(lanternOutput("var i = 0\nwhile i < 3 { print(i)\ni += 1 }") == "0\n1\n2")
    }
    @Test func while_never_enters() {
        #expect(lanternOutput("while false { print(1) }\nprint(\"done\")") == "done")
    }
    @Test func for_range_exclusive() {
        #expect(lanternOutput("for i in 0..<3 { print(i) }") == "0\n1\n2")
    }
    @Test func for_range_inclusive() {
        #expect(lanternOutput("for i in 1...3 { print(i) }") == "1\n2\n3")
    }
    @Test func nested_if() {
        let src = """
        let x = 10
        if x > 5 {
            if x > 8 {
                print("very big")
            } else {
                print("medium")
            }
        }
        """
        #expect(lanternOutput(src) == "very big")
    }
    @Test func local_scope() {
        let src = """
        var x = 1
        if true {
            var x = 2
            print(x)
        }
        print(x)
        """
        #expect(lanternOutput(src) == "2\n1")
    }
}
