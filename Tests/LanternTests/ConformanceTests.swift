import Testing
import Foundation
@testable import Lantern

// MARK: - Conformance Test Runner
//
// Parses the same fixture files used by the Swift compiler conformance runner
// and runs each test through the Lantern interpreter. Tests that produce
// identical output to the real compiler are confirmed correct.

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

func runLanternTest(_ test: ConformanceTestCase) -> (output: String, error: String?) {
    let interpreter = Interpreter()
    let output = CapturedOutputHandler()
    interpreter.outputHandler = output

    let result = interpreter.run(source: test.source, fileName: test.fileName)

    let captured = output.printOutput.joined()
        .trimmingCharacters(in: .newlines)

    switch result {
    case .success:
        return (captured, nil)
    case .failure(let err):
        return (captured, err.description)
    }
}

// MARK: - Test Suite
//
// This runs all 351 conformance fixtures through the Lantern interpreter.
// At this stage of development most will fail (the interpreter doesn't
// implement all features yet). Each passing test confirms that Lantern
// produces output identical to the real Swift compiler for that case.

@Suite("Conformance")
struct ConformanceTests {
    static let fixtures = loadAllFixtures()

    @Test("Fixture files found")
    func fixturesExist() {
        #expect(Self.fixtures.count > 0, "No fixture files found — check Fixtures/Conformance/ directory")
    }

    // Run only Phase 1 arithmetic fixtures for now (the VM can handle these)
    @Test("Phase 1 — Arithmetic conformance", arguments: loadAllFixtures().filter { $0.fileName.hasPrefix("01_") })
    func arithmeticConformance(test: ConformanceTestCase) {
        let (output, error) = runLanternTest(test)
        if let error {
            Issue.record("[\(test.fileName):\(test.lineNumber)] \(test.name) — \(error)")
            return
        }
        #expect(output == test.expectedOutput,
                "[\(test.fileName):\(test.lineNumber)] \(test.name)\n  Expected: \(test.expectedOutput)\n  Actual:   \(output)")
    }
}

// Make ConformanceTestCase work with @Test arguments
extension ConformanceTestCase: CustomTestStringConvertible {
    var testDescription: String { "\(fileName):\(name)" }
}
