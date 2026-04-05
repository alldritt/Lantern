import Testing
@testable import Lantern
@testable import LanternVM

@Suite("Append Bug Isolation")
struct AppendBugTests {
    func run(_ source: String, limit: Int = 50_000) -> (output: String, steps: Int, error: String?) {
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

    @Test func appendConstant() {
        let (out, steps, err) = run("var a = [1, 2]; a.append(3); print(a)")
        print("  append(3): steps=\(steps) out='\(out)' err=\(err ?? "none")")
        #expect(out == "[1, 2, 3]")
    }

    @Test func appendFromVariable() {
        let (out, steps, err) = run("var a = [1, 2]; let x = 3; a.append(x); print(a)")
        print("  append(x): steps=\(steps) out='\(out)' err=\(err ?? "none")")
        #expect(out == "[1, 2, 3]")
    }

    @Test func appendFromSubscript() {
        let (out, steps, err) = run("var a = [10, 20]; a.append(a[0]); print(a)")
        print("  append(a[0]): steps=\(steps) out='\(out)' err=\(err ?? "none")")
    }

    @Test func appendFromCount() {
        let (out, steps, err) = run("var a = [1, 2]; a.append(a.count); print(a)")
        print("  append(a.count): steps=\(steps) out='\(out)' err=\(err ?? "none")")
    }

    @Test func appendComputedValue() {
        let (out, steps, err) = run("var a = [10, 20]; a.append(a[0] + a[1]); print(a)")
        print("  append(a[0]+a[1]): steps=\(steps) out='\(out)' err=\(err ?? "none")")
    }

    @Test func appendWithCountMinusOne() {
        let (out, steps, err) = run("var a = [10, 20]; a.append(a[a.count - 1]); print(a)")
        print("  append(a[a.count-1]): steps=\(steps) out='\(out)' err=\(err ?? "none")")
    }

    @Test func appendWithCountMinusOnePlusCountMinusTwo() {
        let (out, steps, err) = run("var a = [10, 20]; a.append(a[a.count - 1] + a[a.count - 2]); print(a)")
        print("  append(a[cnt-1]+a[cnt-2]): steps=\(steps) out='\(out)' err=\(err ?? "none")")
    }

    @Test func justSubscriptWithCount() {
        let (out, steps, err) = run("var a = [10, 20]; let v = a[a.count - 1]; print(v)")
        print("  a[a.count-1] read: steps=\(steps) out='\(out)' err=\(err ?? "none")")
    }
}
