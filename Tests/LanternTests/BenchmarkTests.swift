import Testing
import Foundation
@testable import Lantern
@testable import LanternVM

// MARK: - Benchmark Infrastructure

struct BenchmarkResult {
    let name: String
    let iterations: Int
    let totalTime: Double // seconds
    let opsPerSecond: Double
    var timePerOp: Double { totalTime / Double(iterations) }

    var summary: String {
        let ms = timePerOp * 1000
        return String(format: "%-35s %8.2f ms  (%,.0f ops/s)", name, ms, opsPerSecond)
    }
}

func benchmark(_ name: String, iterations: Int = 5, _ block: () -> Void) -> BenchmarkResult {
    // Warmup
    block()

    var total: Double = 0
    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        total += CFAbsoluteTimeGetCurrent() - start
    }

    let avg = total / Double(iterations)
    return BenchmarkResult(name: name, iterations: iterations, totalTime: total, opsPerSecond: 1.0 / avg)
}

func runInterpreter(source: String, stepLimit: Int = 5_000_000) -> (result: Result<Value, InterpreterError>, timeMs: Double) {
    let interp = Interpreter()
    interp.maxExecutionSteps = stepLimit
    let output = CapturedOutputHandler()
    interp.outputHandler = output

    let start = CFAbsoluteTimeGetCurrent()
    let result = interp.run(source: source)
    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

    return (result, elapsed)
}

// MARK: - Benchmark Suite

@Suite("Performance Benchmarks")
struct PerformanceBenchmarks {

    // MARK: - Arithmetic / VM Dispatch

    @Test func tightArithmeticLoop() {
        let src = """
        var sum = 0
        for i in 0..<10000 {
            sum = sum + i
        }
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  tightArithmeticLoop:              %8.2f ms", ms))
        } else {
            print("  tightArithmeticLoop: FAILED - \(result)")
        }
        #expect(ms < 5000, "Arithmetic loop should complete in under 5s")
    }

    @Test func nestedArithmeticLoop() {
        let src = """
        var sum = 0
        for i in 0..<100 {
            for j in 0..<100 {
                sum = sum + i + j
            }
        }
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  nestedArithmeticLoop:             %8.2f ms", ms))
        } else {
            print("  nestedArithmeticLoop: FAILED - \(result)")
        }
        #expect(ms < 5000, "Nested loop should complete in under 5s")
    }

    // MARK: - Function Calls

    @Test func recursiveFibonacci() {
        let src = """
        func fib(_ n: Int) -> Int {
            if n <= 1 { return n }
            return fib(n - 1) + fib(n - 2)
        }
        fib(15)
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  recursiveFibonacci(15):           %8.2f ms", ms))
        } else {
            print("  recursiveFibonacci: FAILED - \(result)")
        }
        #expect(ms < 5000, "fib(15) should complete in under 5s")
    }

    @Test func functionCallOverhead() {
        let src = """
        func identity(_ x: Int) -> Int { return x }
        var sum = 0
        for i in 0..<5000 {
            sum = sum + identity(i)
        }
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  functionCallOverhead:             %8.2f ms", ms))
        } else {
            print("  functionCallOverhead: FAILED - \(result)")
        }
        #expect(ms < 5000)
    }

    // MARK: - Closures / Higher-Order

    @Test func closureInvocation() {
        let src = """
        let add = { (a: Int, b: Int) in a + b }
        var sum = 0
        for i in 0..<1000 {
            sum = add(sum, i)
        }
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  closureInvocation:                %8.2f ms", ms))
        } else {
            print("  closureInvocation: FAILED - \(result)")
        }
        #expect(ms < 5000)
    }

    @Test func mapFilterReduce() {
        let src = """
        let arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        let result = arr
            .map { $0 * $0 }
            .filter { $0 > 10 }
            .reduce(0, +)
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  mapFilterReduce:                  %8.2f ms", ms))
        } else {
            print("  mapFilterReduce: FAILED - \(result)")
        }
        #expect(ms < 5000)
    }

    // MARK: - Array Operations

    @Test func arrayAppendLoop() {
        let src = """
        var arr: [Int] = []
        for i in 0..<500 {
            arr.append(i)
        }
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  arrayAppendLoop(500):             %8.2f ms", ms))
        } else {
            print("  arrayAppendLoop: FAILED - \(result)")
        }
        #expect(ms < 5000)
    }

    @Test func arraySubscriptAccess() {
        let src = """
        let arr = [10, 20, 30, 40, 50]
        var sum = 0
        for i in 0..<1000 {
            sum = sum + arr[i % 5]
        }
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  arraySubscriptAccess:             %8.2f ms", ms))
        } else {
            print("  arraySubscriptAccess: FAILED - \(result)")
        }
        #expect(ms < 5000)
    }

    // MARK: - Property Access

    @Test func structPropertyAccess() {
        let src = """
        struct Point {
            var x: Int
            var y: Int
        }
        var p = Point(x: 0, y: 0)
        for i in 0..<1000 {
            p.x = p.x + 1
            p.y = p.y + 2
        }
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  structPropertyAccess:             %8.2f ms", ms))
        } else {
            print("  structPropertyAccess: FAILED - \(result)")
        }
        #expect(ms < 5000)
    }

    @Test func computedPropertyAccess() {
        let src = """
        struct Counter {
            var value: Int
            var doubled: Int { value * 2 }
        }
        var c = Counter(value: 0)
        var sum = 0
        for i in 0..<500 {
            c.value = i
            sum = sum + c.doubled
        }
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  computedPropertyAccess:           %8.2f ms", ms))
        } else {
            print("  computedPropertyAccess: FAILED - \(result)")
        }
        #expect(ms < 5000)
    }

    // MARK: - Dictionary Operations

    @Test func dictionaryLookup() {
        let src = """
        var dict: [String: Int] = [:]
        for i in 0..<200 {
            dict["key\\(i)"] = i
        }
        var sum = 0
        for i in 0..<200 {
            if let val = dict["key\\(i)"] {
                sum = sum + val
            }
        }
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  dictionaryLookup(200):            %8.2f ms", ms))
        } else {
            print("  dictionaryLookup: FAILED - \(result)")
        }
        #expect(ms < 5000)
    }

    // MARK: - String Operations

    @Test func stringConcatenation() {
        let src = """
        var s = ""
        for i in 0..<500 {
            s = s + "x"
        }
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  stringConcatenation(500):         %8.2f ms", ms))
        } else {
            print("  stringConcatenation: FAILED - \(result)")
        }
        #expect(ms < 5000)
    }

    @Test func stringInterpolation() {
        let src = """
        var result = ""
        for i in 0..<200 {
            result = "item \\(i)"
        }
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  stringInterpolation(200):         %8.2f ms", ms))
        } else {
            print("  stringInterpolation: FAILED - \(result)")
        }
        #expect(ms < 5000)
    }

    // MARK: - Conformance Timeout Programs

    @Test func conformanceFibonacciSequence() {
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
        fibSequence(10)
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  fibonacciSequence(10):            %8.2f ms", ms))
        } else {
            print("  fibonacciSequence: FAILED - \(result)")
        }
        #expect(ms < 5000)
    }

    @Test func conformanceStackImplementation() {
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
        var sum = 0
        while let item = stack.pop() {
            sum = sum + item
        }
        """
        let (result, ms) = runInterpreter(source: src)
        if case .success = result {
            print(String(format: "  stackImplementation:              %8.2f ms", ms))
        } else {
            print("  stackImplementation: FAILED - \(result)")
        }
        #expect(ms < 5000)
    }

    // MARK: - Compilation Time

    @Test func compilationTime() {
        let src = """
        struct Person {
            var name: String
            var age: Int
            var isAdult: Bool { age >= 18 }
            func greet() -> String { return "Hello, \\(name)!" }
        }
        func process(_ people: [Person]) -> [String] {
            return people.filter { $0.isAdult }.map { $0.greet() }
        }
        let people = [
            Person(name: "Alice", age: 30),
            Person(name: "Bob", age: 15),
            Person(name: "Charlie", age: 25)
        ]
        process(people)
        """
        let interp = Interpreter()
        let start = CFAbsoluteTimeGetCurrent()
        let _ = interp.compile(source: src)
        let compileMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "  compilationTime (struct+funcs):    %8.2f ms", compileMs))
        #expect(compileMs < 2000, "Compilation should be under 2s")
    }

    // MARK: - Summary

    @Test func printBenchmarkSummary() {
        print("\n=== PERFORMANCE BENCHMARK RESULTS ===\n")
        print("(Individual results printed by each test above)")
        print("Threshold: all benchmarks must complete in < 5000ms")
        print("Step limit: 5,000,000")
        print("")
    }
}
