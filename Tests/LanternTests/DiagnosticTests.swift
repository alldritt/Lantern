import Testing
import Foundation
@testable import Lantern
@testable import LanternVM

/// Isolate specific patterns to find bugs vs overhead
@Suite("Pattern Diagnostics")
struct PatternDiagnostics {

    func run(_ source: String, limit: Int = 100_000) -> (output: String, steps: Int, error: String?) {
        let interp = Interpreter()
        interp.maxExecutionSteps = limit
        let output = CapturedOutputHandler()
        interp.outputHandler = output
        let vm = (interp.debugger as! Debugger).vm
        let result = interp.run(source: source)
        let steps = vm.executionCount
        let captured = output.printOutput.joined().trimmingCharacters(in: .newlines)
        switch result {
        case .success: return (captured, steps, nil)
        case .failure(let err): return (captured, steps, "\(err.kind): \(err.message)")
        }
    }

    // MARK: - Isolate: arr.count property

    @Test func arrayCountProperty() {
        let (out, steps, err) = run("let arr = [1, 2, 3]; print(arr.count)")
        print("  arr.count: steps=\(steps) output='\(out)' err=\(err ?? "none")")
        #expect(out == "3")
        #expect(err == nil)
    }

    // MARK: - Isolate: arr[arr.count - 1]

    @Test func arraySubscriptWithCount() {
        let (out, steps, err) = run("let arr = [10, 20, 30]; print(arr[arr.count - 1])")
        print("  arr[arr.count-1]: steps=\(steps) output='\(out)' err=\(err ?? "none")")
        #expect(out == "30")
        #expect(err == nil)
    }

    // MARK: - Isolate: arr.append + arr[arr.count - 1]

    @Test func appendThenSubscript() {
        let src = """
        var fibs = [0, 1]
        fibs.append(fibs[fibs.count - 1] + fibs[fibs.count - 2])
        print(fibs)
        """
        let (out, steps, err) = run(src)
        print("  append+subscript: steps=\(steps) output='\(out)' err=\(err ?? "none")")
        #expect(out == "[0, 1, 1]")
    }

    // MARK: - Isolate: loop with append + subscript (2 iterations)

    @Test func fibLoop2Iterations() {
        let src = """
        var fibs = [0, 1]
        for _ in 2..<4 {
            fibs.append(fibs[fibs.count - 1] + fibs[fibs.count - 2])
        }
        print(fibs)
        """
        let (out, steps, err) = run(src, limit: 500_000)
        print("  fib loop 2 iters: steps=\(steps) output='\(out)' err=\(err ?? "none")")
        #expect(out == "[0, 1, 1, 2]")
    }

    // MARK: - Isolate: struct method returning optional

    @Test func structMethodReturnsOptional() {
        let src = """
        struct S {
            var items: [Int] = [1, 2, 3]
            func pop() -> Int? {
                return items.isEmpty ? nil : items.last
            }
        }
        let s = S()
        print(s.pop()!)
        """
        let (out, steps, err) = run(src)
        print("  struct optional method: steps=\(steps) output='\(out)' err=\(err ?? "none")")
        #expect(out == "3")
    }

    // MARK: - Isolate: while let with struct method

    @Test func whileLetWithStructMethod() {
        let src = """
        struct S {
            var items: [Int] = [1, 2]
            mutating func take() -> Int? {
                if items.isEmpty { return nil }
                return items.removeLast()
            }
        }
        var s = S()
        while let item = s.take() {
            print(item)
        }
        """
        let (out, steps, err) = run(src, limit: 500_000)
        print("  while let struct: steps=\(steps) output='\(out)' err=\(err ?? "none")")
    }

    // MARK: - Isolate: mutating method store-back

    @Test func mutatingMethodStoreBack() {
        let src = """
        struct Box {
            var value: Int = 0
            mutating func increment() { value = value + 1 }
        }
        var b = Box()
        b.increment()
        b.increment()
        print(b.value)
        """
        let (out, steps, err) = run(src)
        print("  mutating store-back: steps=\(steps) output='\(out)' err=\(err ?? "none")")
        #expect(out == "2")
    }
}
