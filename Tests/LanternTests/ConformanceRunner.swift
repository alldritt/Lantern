import Testing
import Foundation
@testable import Lantern
@testable import LanternVM

/// Runs conformance fixtures through the Lantern interpreter.
@Suite("Conformance Runner")
struct ConformanceRunner {
    @Test func runAllConformanceFixtures() {
        guard let dir = findFixturesDirectory() else { return }

        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let fixtureFiles = files
            .filter { $0.hasSuffix(".swift") && !$0.contains("conformance_runner") }
            .sorted()

        var totalPassed = 0
        var totalFailed = 0
        var report: [String] = []

        for file in fixtureFiles {
            let tests = parseFixtureFile(at: "\(dir)/\(file)")
            if tests.isEmpty { continue }

            var filePassed = 0
            var fileFailed = 0
            var fileErrors: [String] = []

            for test in tests {
                let (captured, error) = runTestWithTimeout(test, timeoutMs: 500)

                if let error {
                    fileFailed += 1
                    fileErrors.append("  \(test.name): \(error.prefix(60))")
                } else if captured == test.expectedOutput {
                    filePassed += 1
                } else {
                    fileFailed += 1
                    fileErrors.append("  \(test.name): expected[\(test.expectedOutput.prefix(40))] got[\(captured.prefix(40))]")
                }
            }

            totalPassed += filePassed
            totalFailed += fileFailed
            let status = fileFailed == 0 ? "ALL PASS" : "\(filePassed)/\(filePassed + fileFailed)"
            report.append("\(file): \(status)")
            if !fileErrors.isEmpty { report.append(contentsOf: fileErrors.prefix(5)) }
        }

        let total = totalPassed + totalFailed
        report.insert("=== Conformance: \(totalPassed)/\(total) passed ===", at: 0)
        print("\n" + report.joined(separator: "\n") + "\n")
    }

    /// Run a single test with a timeout to prevent hangs.
    func runTestWithTimeout(_ test: ConformanceTestCase, timeoutMs: Int) -> (output: String, error: String?) {
        let semaphore = DispatchSemaphore(value: 0)
        var resultOutput = ""
        var resultError: String? = nil

        DispatchQueue.global().async {
            let interp = Interpreter()
            let output = CapturedOutputHandler()
            interp.outputHandler = output
            interp.maxExecutionSteps = 50_000

            let result = interp.run(source: test.source, fileName: test.fileName)
            let captured = output.printOutput.joined().trimmingCharacters(in: .newlines)

            switch result {
            case .success:
                resultOutput = captured
            case .failure(let err):
                resultError = "\(err.kind) \(err.message)"
            }
            semaphore.signal()
        }

        let timeout = DispatchTime.now() + .milliseconds(timeoutMs)
        if semaphore.wait(timeout: timeout) == .timedOut {
            return ("", "TIMEOUT")
        }
        return (resultOutput, resultError)
    }
}
