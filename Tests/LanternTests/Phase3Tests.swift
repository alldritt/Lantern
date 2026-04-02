import Testing
import Foundation
@testable import Lantern

@Suite("Phase 3 — Functions")
struct Phase3Tests {
    @Test func simple_function() {
        let src = """
        func add(a: Int, b: Int) -> Int {
            return a + b
        }
        print(add(a: 3, b: 4))
        """
        #expect(lanternOutput(src) == "7")
    }

    @Test func function_no_params() {
        let src = """
        func greet() {
            print("hello")
        }
        greet()
        """
        #expect(lanternOutput(src) == "hello")
    }

    @Test func function_with_return() {
        let src = """
        func square(x: Int) -> Int {
            return x * x
        }
        print(square(x: 5))
        """
        #expect(lanternOutput(src) == "25")
    }

    @Test func two_function_calls() {
        let src = """
        func double(x: Int) -> Int {
            return x * 2
        }
        let a = double(x: 3)
        let b = double(x: a)
        print(b)
        """
        #expect(lanternOutput(src) == "12")
    }

    @Test func nested_calls() {
        let src = """
        func double(x: Int) -> Int {
            return x * 2
        }
        print(double(x: double(x: 3)))
        """
        #expect(lanternOutput(src) == "12")
    }

    @Test func recursion_factorial() {
        let src = """
        func factorial(n: Int) -> Int {
            if n <= 1 { return 1 }
            return n * factorial(n: n - 1)
        }
        print(factorial(n: 5))
        """
        #expect(lanternOutput(src) == "120")
    }

    @Test func multiple_statements_in_function() {
        let src = """
        func compute(x: Int) -> Int {
            var result = x
            result = result * 2
            result = result + 10
            return result
        }
        print(compute(x: 5))
        """
        #expect(lanternOutput(src) == "20")
    }

    @Test func string_interpolation() {
        let src = #"let name = "World"\#nprint("Hello \(name)")"#
        #expect(lanternOutput(src) == "Hello World")
    }

    @Test func string_interpolation_expression() {
        let src = #"print("2 + 3 = \(2 + 3)")"#
        #expect(lanternOutput(src) == "2 + 3 = 5")
    }

    @Test func simple_reassignment() {
        let src = "var x = 10\nx = 20\nprint(x)"
        #expect(lanternOutput(src) == "20")
    }

    @Test func for_loop_print_sum_each_iter() {
        let src = "var sum = 0\nfor i in 1...3 {\n    sum = sum + i\n    print(sum)\n}"
        #expect(lanternOutput(src) == "1\n3\n6")
    }

    @Test func for_loop_simple_assign() {
        let src = "var x = 0\nfor i in 1...3 {\n    x = i\n}\nprint(x)"
        #expect(lanternOutput(src) == "3")
    }

    @Test func for_loop_compound_add() {
        let src = "var s = 0\nfor i in 1...3 {\n    s += i\n}\nprint(s)"
        #expect(lanternOutput(src) == "6")
    }

    @Test func for_with_computation() {
        let src = """
        var sum = 0
        for i in 1...10 {
            sum += i
        }
        print(sum)
        """
        #expect(lanternOutput(src) == "55")
    }

    @Test func for_with_explicit_assign() {
        // This tests `sum = sum + i` (separate = and +)
        let src = """
        var sum = 0
        for i in 1...3 {
            sum = sum + i
        }
        print(sum)
        """
        #expect(lanternOutput(src) == "6")
    }

    @Test func fizzbuzz_simple() {
        let src = """
        for i in 1...15 {
            if i % 15 == 0 {
                print("FizzBuzz")
            } else if i % 3 == 0 {
                print("Fizz")
            } else if i % 5 == 0 {
                print("Buzz")
            } else {
                print(i)
            }
        }
        """
        let expected = "1\n2\nFizz\n4\nBuzz\nFizz\n7\n8\nFizz\nBuzz\n11\nFizz\n13\n14\nFizzBuzz"
        #expect(lanternOutput(src) == expected)
    }
}
