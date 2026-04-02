#!/usr/bin/env swift

// Lantern Conformance Test Runner
//
// Parses .swift fixture files with annotated test cases,
// runs each through the Swift compiler, and captures expected output.
//
// Usage:
//   swift conformance_runner.swift <fixtures_directory>
//
// Fixture format:
//   // TEST: test_name
//   // EXPECT: expected line 1
//   // expected line 2
//   <swift source>
//   // END

import Foundation

struct TestCase {
    let name: String
    let expectedOutput: String
    let source: String
    let fileName: String
    let lineNumber: Int
}

struct TestResult {
    let testCase: TestCase
    let actualOutput: String
    let passed: Bool
    let error: String?
}

// MARK: - Fixture Parser

func parseFixtures(at path: String) -> [TestCase] {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("Error: Could not read \(path)")
        return []
    }

    let fileName = URL(fileURLWithPath: path).lastPathComponent
    let lines = content.components(separatedBy: "\n")
    var tests: [TestCase] = []
    var i = 0

    while i < lines.count {
        let line = lines[i].trimmingCharacters(in: .whitespaces)

        if line.hasPrefix("// TEST:") {
            let name = line.replacingOccurrences(of: "// TEST:", with: "").trimmingCharacters(in: .whitespaces)
            let testLineNumber = i + 1
            i += 1

            // Parse EXPECT lines
            var expectedLines: [String] = []
            while i < lines.count {
                let expectLine = lines[i].trimmingCharacters(in: .whitespaces)
                if expectLine.hasPrefix("// EXPECT:") {
                    expectedLines.append(
                        expectLine.replacingOccurrences(of: "// EXPECT:", with: "")
                            .trimmingCharacters(in: .init(charactersIn: " "))
                    )
                    i += 1
                } else if expectLine.hasPrefix("//") && !expectLine.hasPrefix("// TEST:") && !expectLine.hasPrefix("// END") && !expectedLines.isEmpty {
                    let continued = expectLine.replacingOccurrences(of: "//", with: "")
                        .trimmingCharacters(in: .init(charactersIn: " "))
                    expectedLines.append(continued)
                    i += 1
                } else {
                    break
                }
            }

            // Parse source until // END
            var sourceLines: [String] = []
            while i < lines.count {
                let srcLine = lines[i]
                if srcLine.trimmingCharacters(in: .whitespaces) == "// END" {
                    i += 1
                    break
                }
                sourceLines.append(srcLine)
                i += 1
            }

            let expectedOutput = expectedLines.joined(separator: "\n")
            let source = sourceLines.joined(separator: "\n")

            tests.append(TestCase(
                name: name,
                expectedOutput: expectedOutput,
                source: source,
                fileName: fileName,
                lineNumber: testLineNumber
            ))
        } else {
            i += 1
        }
    }

    return tests
}

// MARK: - Swift Compiler Runner

func runSwift(source: String) -> (output: String, error: String?, exitCode: Int32) {
    let tempDir = NSTemporaryDirectory()
    let sourceFile = tempDir + "lantern_test_\(UUID().uuidString).swift"

    do {
        try source.write(toFile: sourceFile, atomically: true, encoding: .utf8)
    } catch {
        return ("", "Could not write temp file: \(error)", 1)
    }

    defer { try? FileManager.default.removeItem(atPath: sourceFile) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    process.arguments = [sourceFile]

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return ("", "Could not run swift: \(error)", 1)
    }

    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

    let output = String(data: outputData, encoding: .utf8)?
        .trimmingCharacters(in: .newlines) ?? ""
    let errorOutput = String(data: errorData, encoding: .utf8)?
        .trimmingCharacters(in: .newlines) ?? ""

    return (
        output,
        errorOutput.isEmpty ? nil : errorOutput,
        process.terminationStatus
    )
}

// MARK: - Main

func main() {
    let args = CommandLine.arguments

    guard args.count > 1 else {
        print("Usage: swift conformance_runner.swift <fixtures_directory>")
        print("       swift conformance_runner.swift <fixture_file.swift>")
        exit(1)
    }

    let path = args[1]
    var fixtureFiles: [String] = []

    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
        if isDir.boolValue {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            fixtureFiles = files
                .filter { $0.hasSuffix(".swift") && $0 != "conformance_runner.swift" }
                .sorted()
                .map { "\(path)/\($0)" }
        } else {
            fixtureFiles = [path]
        }
    } else {
        print("Error: \(path) does not exist")
        exit(1)
    }

    var totalTests = 0
    var passedTests = 0
    var failedTests = 0
    var errors: [TestResult] = []

    for file in fixtureFiles {
        let tests = parseFixtures(at: file)
        let fileName = URL(fileURLWithPath: file).lastPathComponent

        if tests.isEmpty { continue }
        print("\n--- \(fileName) (\(tests.count) tests) ---")

        for test in tests {
            totalTests += 1
            let (output, error, exitCode) = runSwift(source: test.source)

            let passed: Bool
            if exitCode != 0 {
                passed = false
            } else {
                passed = output == test.expectedOutput
            }

            let result = TestResult(
                testCase: test,
                actualOutput: output,
                passed: passed,
                error: error
            )

            if passed {
                passedTests += 1
                print("  \u{2713} \(test.name)")
            } else {
                failedTests += 1
                errors.append(result)
                print("  \u{2717} \(test.name)")
            }
        }
    }

    // Summary
    print("\n" + String(repeating: "=", count: 50))
    print("Results: \(passedTests)/\(totalTests) passed, \(failedTests) failed")
    print(String(repeating: "=", count: 50))

    if !errors.isEmpty {
        print("\nFailures:\n")
        for result in errors {
            let tc = result.testCase
            print("  \(tc.fileName):\(tc.lineNumber) — \(tc.name)")
            print("    Expected: \(tc.expectedOutput.replacingOccurrences(of: "\n", with: "\n              "))")
            print("    Actual:   \(result.actualOutput.replacingOccurrences(of: "\n", with: "\n              "))")
            if let error = result.error {
                print("    Error:    \(String(error.prefix(200)))")
            }
            print()
        }
    }

    exit(failedTests > 0 ? 1 : 0)
}

main()
