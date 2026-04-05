import Testing
import Foundation
@testable import Lantern
@testable import LanternVM

/// Diagnostic tests to measure how many VM steps simple programs consume.
/// This identifies whether timeouts are from infinite loops or excessive overhead.
@Suite("Step Count Diagnostics")
struct StepCountDiagnostics {

    /// Run source and return (output, steps consumed, error if any)
    func measure(_ source: String, limit: Int = 100_000) -> (output: String, steps: Int, error: String?) {
        let interp = Interpreter()
        interp.maxExecutionSteps = limit
        let output = CapturedOutputHandler()
        interp.outputHandler = output
        let vm = (interp.debugger as! Debugger).vm

        let result = interp.run(source: source)
        let steps = vm.executionCount
        let captured = output.printOutput.joined()

        switch result {
        case .success:
            return (captured, steps, nil)
        case .failure(let err):
            return (captured, steps, "\(err.kind): \(err.message)")
        }
    }

    // MARK: - Baseline: How many steps per iteration?

    @Test func emptyLoop100() {
        let (_, steps, err) = measure("for _ in 0..<100 { }")
        print("  empty loop 100 iterations:     \(steps) steps (\(steps/100) per iteration)")
        #expect(err == nil)
    }

    @Test func addInLoop100() {
        let (_, steps, err) = measure("var x = 0; for _ in 0..<100 { x = x + 1 }")
        print("  x = x + 1 loop 100 iterations: \(steps) steps (\(steps/100) per iteration)")
        #expect(err == nil)
    }

    @Test func functionCallInLoop100() {
        let src = """
        func inc(_ x: Int) -> Int { return x + 1 }
        var n = 0
        for _ in 0..<100 { n = inc(n) }
        """
        let (_, steps, err) = measure(src)
        print("  func call loop 100 iterations: \(steps) steps (\(steps/100) per iteration)")
        #expect(err == nil)
    }

    @Test func arrayAppendLoop50() {
        let src = """
        var arr: [Int] = []
        for i in 0..<50 { arr.append(i) }
        """
        let (_, steps, err) = measure(src)
        print("  arr.append loop 50 iterations: \(steps) steps (\(steps/50) per iteration)")
        #expect(err == nil)
    }

    @Test func propertyAccessLoop100() {
        let src = """
        struct P { var x: Int }
        var p = P(x: 0)
        for _ in 0..<100 { p.x = p.x + 1 }
        """
        let (_, steps, err) = measure(src)
        print("  p.x = p.x + 1 loop 100 iters: \(steps) steps (\(steps/100) per iteration)")
        #expect(err == nil)
    }

    @Test func closureCallLoop100() {
        let src = """
        let f = { (x: Int) in x + 1 }
        var n = 0
        for _ in 0..<100 { n = f(n) }
        """
        let (_, steps, err) = measure(src)
        print("  closure call loop 100 iters:   \(steps) steps (\(steps/100) per iteration)")
        #expect(err == nil)
    }

    @Test func subscriptAccessLoop100() {
        let src = """
        let arr = [10, 20, 30, 40, 50]
        var sum = 0
        for i in 0..<100 { sum = sum + arr[i % 5] }
        """
        let (_, steps, err) = measure(src)
        print("  arr[i] access loop 100 iters:  \(steps) steps (\(steps/100) per iteration)")
        #expect(err == nil)
    }

    // MARK: - The failing conformance programs

    @Test func fibonacciSequence10() {
        let src = """
        func fibSequence(_ count: Int) -> [Int] {
            if count <= 0 { return [] }
            if count == 1 { return [0] }
            var fibs = [0, 1]
            for _ in 2..<count {
                fibs.append(fibs[fibs.count - 1] + fibs[fibs.count - 2])
            }
            return fibs
        }
        print(fibSequence(10))
        """
        let (output, steps, err) = measure(src, limit: 5_000_000)
        print("  fibSequence(10):               \(steps) steps  error=\(err ?? "none")")
        print("    output: \(output.prefix(60))")
    }

    @Test func stackImplementation() {
        let src = """
        struct Stack {
            var items: [Int] = []
            var isEmpty: Bool { items.isEmpty }
            mutating func push(_ item: Int) { items.append(item) }
            mutating func pop() -> Int? {
                return items.isEmpty ? nil : items.removeLast()
            }
        }
        var stack = Stack()
        stack.push(1)
        stack.push(2)
        stack.push(3)
        while let item = stack.pop() {
            print(item)
        }
        print("empty: \\(stack.isEmpty)")
        """
        let (output, steps, err) = measure(src, limit: 5_000_000)
        print("  stackImplementation:           \(steps) steps  error=\(err ?? "none")")
        print("    output: \(output.prefix(60))")
    }

    @Test func recursiveFib15() {
        let src = """
        func fib(_ n: Int) -> Int {
            if n <= 1 { return n }
            return fib(n - 1) + fib(n - 2)
        }
        print(fib(15))
        """
        let (output, steps, err) = measure(src, limit: 5_000_000)
        print("  fib(15) recursive:             \(steps) steps  error=\(err ?? "none")")
        print("    output: \(output.prefix(60))")
    }

    @Test func mapFilterOnSmallArray() {
        let src = """
        let arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        let result = arr.map { $0 * $0 }.filter { $0 > 10 }.reduce(0, +)
        print(result)
        """
        let (output, steps, err) = measure(src, limit: 5_000_000)
        print("  map+filter+reduce [10]:        \(steps) steps  error=\(err ?? "none")")
        print("    output: \(output.prefix(60))")
    }
}
