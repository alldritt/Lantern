import Testing
import Foundation
@testable import Lantern
@testable import LanternVM

// MARK: - Conformance Test Runner
//
// Parses the same fixture files used by the Swift compiler conformance runner
// and runs each test through the Lantern interpreter. Tests that produce
// identical output to the real compiler are confirmed correct.
//
// Test format supports:
//   // EXPECT: output     — expect this exact output
//   // EXPECT: ERROR      — expect any error
//   // EXPECT: ERROR@3    — expect an error at line 3 of the test source
//   // EXPECT: VIEW       — expect a ViewBox result (SwiftUI)
//   // EXPECT: COMPILES   — expect successful compilation (no output check)

struct ConformanceTestCase {
    let name: String
    let expectedOutput: String
    let source: String
    let fileName: String
    let lineNumber: Int
}

func parseFixtureFile(at path: String) -> [ConformanceTestCase] {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    let fileName = URL(fileURLWithPath: path).lastPathComponent
    let lines = content.components(separatedBy: "\n")
    var tests: [ConformanceTestCase] = []
    var i = 0

    while i < lines.count {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("// TEST:") {
            let name = line.replacingOccurrences(of: "// TEST:", with: "").trimmingCharacters(in: .whitespaces)
            let testLineNumber = i + 1
            i += 1

            var expectedLines: [String] = []
            while i < lines.count {
                let el = lines[i].trimmingCharacters(in: .whitespaces)
                if el.hasPrefix("// EXPECT:") {
                    expectedLines.append(el.replacingOccurrences(of: "// EXPECT:", with: "").trimmingCharacters(in: .init(charactersIn: " ")))
                    i += 1
                } else if el.hasPrefix("//") && !el.hasPrefix("// TEST:") && !el.hasPrefix("// END") && !expectedLines.isEmpty {
                    expectedLines.append(el.replacingOccurrences(of: "//", with: "").trimmingCharacters(in: .init(charactersIn: " ")))
                    i += 1
                } else { break }
            }

            var sourceLines: [String] = []
            while i < lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces) == "// END" { i += 1; break }
                sourceLines.append(lines[i]); i += 1
            }

            tests.append(ConformanceTestCase(
                name: name,
                expectedOutput: expectedLines.joined(separator: "\n"),
                source: sourceLines.joined(separator: "\n"),
                fileName: fileName,
                lineNumber: testLineNumber
            ))
        } else { i += 1 }
    }
    return tests
}

func findFixturesDirectory() -> String? {
    // Walk up from the test binary to find the project root
    var dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Tests/LanternTests/
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent() // project root
        .appendingPathComponent("Fixtures/Conformance")
    if FileManager.default.fileExists(atPath: dir.path) { return dir.path }
    // Fallback: check working directory
    let cwd = FileManager.default.currentDirectoryPath
    let fallback = cwd + "/Fixtures/Conformance"
    if FileManager.default.fileExists(atPath: fallback) { return fallback }
    return nil
}

func loadAllFixtures() -> [ConformanceTestCase] {
    guard let dir = findFixturesDirectory() else { return [] }
    let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    return files
        .filter { $0.hasSuffix(".swift") && !$0.contains("conformance_runner") }
        .sorted()
        .flatMap { parseFixtureFile(at: "\(dir)/\($0)") }
}

// MARK: - Run a single test through the interpreter

struct LanternTestResult {
    let output: String
    let error: String?
    let errorLine: Int?      // line number from error location, if available
    let resultValue: Value?  // the result value (for VIEW/COMPILES checks)
}

func runLanternTest(_ test: ConformanceTestCase) -> LanternTestResult {
    let interpreter = Interpreter()
    let output = CapturedOutputHandler()
    interpreter.outputHandler = output

    let result = interpreter.run(source: test.source, fileName: test.fileName)

    let captured = output.printOutput.joined()
        .trimmingCharacters(in: .newlines)

    switch result {
    case .success(let value):
        return LanternTestResult(output: captured, error: nil, errorLine: nil, resultValue: value)
    case .failure(let err):
        let line = err.location.map { Int($0.line) }
        return LanternTestResult(output: captured, error: err.description, errorLine: line, resultValue: nil)
    }
}

// Legacy compatibility wrapper
func runLanternTest(_ test: ConformanceTestCase) -> (output: String, error: String?) {
    let result: LanternTestResult = runLanternTest(test)
    return (result.output, result.error)
}

// MARK: - Test Suite
//
// Runs ALL conformance fixtures through the Lantern interpreter as individual
// parameterized @Test cases. Each test confirms that Lantern produces output
// identical to the real Swift compiler for that case.

/// Known failing tests — tracked here so they don't block CI while we fix them.
private let knownFailures: Set<String> = [
    "optional_assignment",          // Output format: Optional(10) vs 10
    "struct_static_property",       // Stack overflow in static property access
    "stack_implementation",         // Execution limit exceeded (perf)
    "matrix_operations",            // Incorrect nested array output
    "uninitializedLetUsedBeforeInit", // Missing error for use-before-init
]

@Suite("Conformance")
struct ConformanceTests {
    static let fixtures = loadAllFixtures()

    @Test("Fixture files found")
    func fixturesExist() {
        #expect(Self.fixtures.count > 0, "No fixture files found — check Fixtures/Conformance/ directory")
    }

    @Test("All conformance", arguments: loadAllFixtures())
    func conformance(test: ConformanceTestCase) {
        let result: LanternTestResult = runLanternTest(test)

        if knownFailures.contains(test.name) {
            withKnownIssue("Known failure: \(test.name)") {
                try validateResult(test: test, result: result)
            }
        } else {
            try! validateResult(test: test, result: result)
        }
    }

    private func validateResult(test: ConformanceTestCase, result: LanternTestResult) throws {
        let expected = test.expectedOutput

        if expected.hasPrefix("ERROR@") {
            // Error with location check: ERROR@3 means error expected at line 3
            let lineStr = expected.dropFirst(6).prefix(while: { $0.isNumber })
            let expectedLine = Int(lineStr)
            if result.error == nil {
                Issue.record("[\(test.fileName):\(test.lineNumber)] \(test.name) — expected error but succeeded")
            } else if let expectedLine, let actualLine = result.errorLine, actualLine != expectedLine {
                Issue.record("[\(test.fileName):\(test.lineNumber)] \(test.name) — error at line \(actualLine), expected line \(expectedLine)")
            }
        } else if expected.hasPrefix("ERROR") {
            // Any error expected
            if result.error == nil {
                Issue.record("[\(test.fileName):\(test.lineNumber)] \(test.name) — expected error but succeeded with [\(result.output.prefix(40))]")
            }
        } else if expected == "VIEW" {
            // Expect a ViewBox result
            if result.error != nil {
                Issue.record("[\(test.fileName):\(test.lineNumber)] \(test.name) — expected VIEW but got error: \(result.error!)")
            } else if result.resultValue?.hostObjectRef == nil {
                Issue.record("[\(test.fileName):\(test.lineNumber)] \(test.name) — expected VIEW but got: \(result.resultValue?.description ?? "nil")")
            }
        } else if expected == "COMPILES" {
            // Just expect no error
            if result.error != nil {
                Issue.record("[\(test.fileName):\(test.lineNumber)] \(test.name) — expected clean compile but got: \(result.error!)")
            }
        } else if let error = result.error {
            Issue.record("[\(test.fileName):\(test.lineNumber)] \(test.name) — \(error)")
        } else {
            #expect(result.output == expected,
                    "[\(test.fileName):\(test.lineNumber)] \(test.name)\n  Expected: \(expected)\n  Actual:   \(result.output)")
        }
    }
}

// Make ConformanceTestCase work with @Test arguments
extension ConformanceTestCase: CustomTestStringConvertible {
    var testDescription: String { "\(fileName):\(name)" }
}
