import Testing
import Foundation
@testable import Lantern
@testable import LanternVM
#if canImport(SwiftUI)
@testable import LanternSwiftUI
#endif

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
                let (captured, error, resultValue) = runTestWithTimeout(test, timeoutMs: 500)
                let expected = test.expectedOutput

                if expected.hasPrefix("ERROR") {
                    // Negative test: expect a compile-time or runtime error
                    if error != nil {
                        filePassed += 1
                    } else {
                        fileFailed += 1
                        fileErrors.append("  \(test.name): expected error but succeeded with [\(captured.prefix(40))]")
                    }
                } else if expected == "VIEW" {
                    // Expect a ViewBox result
                    if error != nil {
                        fileFailed += 1
                        fileErrors.append("  \(test.name): expected VIEW but error: \(error!.prefix(60))")
                    } else if resultValue?.hostObjectRef != nil {
                        filePassed += 1
                    } else {
                        fileFailed += 1
                        fileErrors.append("  \(test.name): expected VIEW but got \(resultValue?.description.prefix(40) ?? "nil")")
                    }
                } else if expected == "COMPILES" {
                    if error != nil {
                        fileFailed += 1
                        fileErrors.append("  \(test.name): expected COMPILES but error: \(error!.prefix(60))")
                    } else {
                        filePassed += 1
                    }
                } else if let error {
                    fileFailed += 1
                    fileErrors.append("  \(test.name): \(error.prefix(60))")
                } else if captured == expected {
                    filePassed += 1
                } else {
                    fileFailed += 1
                    fileErrors.append("  \(test.name): expected[\(expected.prefix(40))] got[\(captured.prefix(40))]")
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
    func runTestWithTimeout(_ test: ConformanceTestCase, timeoutMs: Int) -> (output: String, error: String?, resultValue: Value?) {
        let semaphore = DispatchSemaphore(value: 0)
        var resultOutput = ""
        var resultError: String? = nil
        nonisolated(unsafe) var resultValue: Value? = nil

        DispatchQueue.global().async {
            let interp = Interpreter()
            let output = CapturedOutputHandler()
            interp.outputHandler = output
            interp.maxExecutionSteps = 500_000

            let result = interp.run(source: test.source, fileName: test.fileName)
            let captured = output.printOutput.joined().trimmingCharacters(in: .newlines)

            switch result {
            case .success(let value):
                resultOutput = captured
                resultValue = value
            case .failure(let err):
                resultError = "\(err.kind) \(err.message)"
            }
            semaphore.signal()
        }

        let timeout = DispatchTime.now() + .milliseconds(1000)
        if semaphore.wait(timeout: timeout) == .timedOut {
            return ("", "TIMEOUT", nil)
        }
        return (resultOutput, resultError, resultValue)
    }
}
