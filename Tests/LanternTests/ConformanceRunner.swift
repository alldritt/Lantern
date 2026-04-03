import Testing
import Foundation
@testable import Lantern
@testable import LanternVM

/// Runs conformance fixtures through the Lantern interpreter.
/// Reports pass/fail/error counts per fixture file.
@Suite("Conformance Runner")
struct ConformanceRunner {
    @Test func runAllConformanceFixtures() {
        guard let dir = findFixturesDirectory() else {
            Issue.record("Fixtures directory not found"); return
        }

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
                let interp = Interpreter()
                let output = CapturedOutputHandler()
                interp.outputHandler = output
                interp.maxExecutionSteps = 10_000 // cap per test to prevent hangs

                let result = interp.run(source: test.source, fileName: test.fileName)
                let captured = output.printOutput.joined().trimmingCharacters(in: .newlines)

                switch result {
                case .success:
                    if captured == test.expectedOutput {
                        filePassed += 1
                    } else {
                        fileFailed += 1
                        fileErrors.append("  \(test.name): expected[\(test.expectedOutput.prefix(40))] got[\(captured.prefix(40))]")
                    }
                case .failure(let err):
                    fileFailed += 1
                    fileErrors.append("  \(test.name): \(err.kind) \(err.message.prefix(60))")
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
        // Always print the report
        print("\n" + report.joined(separator: "\n") + "\n")
    }
}
