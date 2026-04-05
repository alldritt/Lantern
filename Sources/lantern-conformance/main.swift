/// Swift Oracle — Conformance validation tool for Lantern.
///
/// Runs each test fixture through BOTH the real Swift compiler and the Lantern
/// interpreter, then compares results. Reports:
///   MATCH    — identical output
///   MISMATCH — both succeed but different output
///   SWIFT_ONLY_ERROR  — Swift rejects it, Lantern accepts (Lantern too permissive)
///   LANTERN_ONLY_ERROR — Lantern rejects it, Swift accepts (Lantern too strict / bug)
///
/// Usage:
///   swift run lantern-conformance [path-to-fixtures-dir]
///   swift run lantern-conformance Fixtures/Conformance/01_arithmetic.swift

import Foundation
import Lantern
import LanternVM

// MARK: - Test Case Parsing (shared with ConformanceTests)

struct TestCase {
    let name: String
    let expectedOutput: String
    let source: String
    let fileName: String
}

func parseFixtures(at path: String) -> [TestCase] {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    let fileName = URL(fileURLWithPath: path).lastPathComponent
    let lines = content.components(separatedBy: "\n")
    var tests: [TestCase] = []
    var i = 0

    while i < lines.count {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("// TEST:") {
            let name = line.replacingOccurrences(of: "// TEST:", with: "").trimmingCharacters(in: .whitespaces)
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

            tests.append(TestCase(
                name: name,
                expectedOutput: expectedLines.joined(separator: "\n"),
                source: sourceLines.joined(separator: "\n"),
                fileName: fileName
            ))
        } else { i += 1 }
    }
    return tests
}

// MARK: - Swift Compiler Execution

enum RunResult {
    case success(String)  // output
    case error(String)    // error message
    case timeout
}

func runSwift(_ source: String) -> RunResult {
    let tmpDir = FileManager.default.temporaryDirectory
    let srcFile = tmpDir.appendingPathComponent("lantern_oracle_\(ProcessInfo.processInfo.processIdentifier).swift")
    let binFile = tmpDir.appendingPathComponent("lantern_oracle_\(ProcessInfo.processInfo.processIdentifier)_bin")

    defer {
        try? FileManager.default.removeItem(at: srcFile)
        try? FileManager.default.removeItem(at: binFile)
    }

    do {
        try source.write(to: srcFile, atomically: true, encoding: .utf8)
    } catch {
        return .error("Failed to write temp file: \(error)")
    }

    // Compile
    let compile = Process()
    compile.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
    compile.arguments = [srcFile.path, "-o", binFile.path, "-suppress-warnings"]
    let compilePipe = Pipe()
    compile.standardError = compilePipe

    do {
        try compile.run()
        compile.waitUntilExit()
    } catch {
        return .error("Failed to launch swiftc: \(error)")
    }

    if compile.terminationStatus != 0 {
        let stderr = String(data: compilePipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return .error(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // Run
    let run = Process()
    run.executableURL = binFile
    let outPipe = Pipe()
    let errPipe = Pipe()
    run.standardOutput = outPipe
    run.standardError = errPipe

    do {
        try run.run()

        // Timeout after 5 seconds
        let deadline = DispatchTime.now() + .seconds(5)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            run.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: deadline) == .timedOut {
            run.terminate()
            return .timeout
        }
    } catch {
        return .error("Failed to run compiled binary: \(error)")
    }

    if run.terminationStatus != 0 {
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return .error("Runtime error: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return .success(output.trimmingCharacters(in: .newlines))
}

// MARK: - Lantern Execution

func runLantern(_ source: String) -> RunResult {
    let interp = Interpreter()
    let output = CapturedOutputHandler()
    interp.outputHandler = output
    interp.maxExecutionSteps = 500_000

    let semaphore = DispatchSemaphore(value: 0)
    var result: RunResult = .timeout

    DispatchQueue.global().async {
        let r = interp.run(source: source)
        let captured = output.printOutput.joined().trimmingCharacters(in: .newlines)
        switch r {
        case .success:
            result = .success(captured)
        case .failure(let err):
            result = .error("\(err.kind): \(err.message)")
        }
        semaphore.signal()
    }

    if semaphore.wait(timeout: .now() + .seconds(2)) == .timedOut {
        return .timeout
    }
    return result
}

// MARK: - Comparison

enum Verdict: String {
    case match = "MATCH"
    case mismatch = "MISMATCH"
    case swiftOnlyError = "SWIFT_ONLY_ERROR"   // Swift rejects, Lantern accepts
    case lanternOnlyError = "LANTERN_ONLY_ERROR" // Lantern rejects, Swift accepts
    case bothError = "BOTH_ERROR"
    case swiftTimeout = "SWIFT_TIMEOUT"
    case lanternTimeout = "LANTERN_TIMEOUT"
}

struct ComparisonResult {
    let test: TestCase
    let verdict: Verdict
    let swiftOutput: String
    let lanternOutput: String
}

func compare(_ test: TestCase) -> ComparisonResult {
    let swift = runSwift(test.source)
    let lantern = runLantern(test.source)

    switch (swift, lantern) {
    case (.success(let s), .success(let l)):
        if s == l {
            return ComparisonResult(test: test, verdict: .match, swiftOutput: s, lanternOutput: l)
        } else {
            return ComparisonResult(test: test, verdict: .mismatch, swiftOutput: s, lanternOutput: l)
        }
    case (.error(let s), .error(let l)):
        return ComparisonResult(test: test, verdict: .bothError, swiftOutput: s, lanternOutput: l)
    case (.error(let s), .success(let l)):
        return ComparisonResult(test: test, verdict: .swiftOnlyError, swiftOutput: s, lanternOutput: l)
    case (.success(let s), .error(let l)):
        return ComparisonResult(test: test, verdict: .lanternOnlyError, swiftOutput: s, lanternOutput: l)
    case (.timeout, _):
        return ComparisonResult(test: test, verdict: .swiftTimeout, swiftOutput: "TIMEOUT", lanternOutput: "")
    case (_, .timeout):
        return ComparisonResult(test: test, verdict: .lanternTimeout, swiftOutput: "", lanternOutput: "TIMEOUT")
    }
}

// MARK: - Main

let args = CommandLine.arguments.dropFirst()
guard let path = args.first else {
    print("Usage: lantern-conformance <fixture-file-or-directory>")
    print("  Compares Lantern output against real Swift compiler for each test case.")
    exit(1)
}

let fm = FileManager.default
var files: [String] = []

var isDir: ObjCBool = false
if fm.fileExists(atPath: path, isDirectory: &isDir) {
    if isDir.boolValue {
        let contents = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        files = contents
            .filter { $0.hasSuffix(".swift") && !$0.contains("conformance_runner") }
            .sorted()
            .map { "\(path)/\($0)" }
    } else {
        files = [path]
    }
}

if files.isEmpty {
    print("No fixture files found at: \(path)")
    exit(1)
}

var totalMatch = 0
var totalMismatch = 0
var totalSwiftOnly = 0
var totalLanternOnly = 0
var totalBothError = 0
var totalTimeout = 0
var issues: [ComparisonResult] = []

for file in files {
    let tests = parseFixtures(at: file)
    let fileName = URL(fileURLWithPath: file).lastPathComponent
    var fileMatch = 0
    var fileIssues = 0

    for test in tests {
        let result = compare(test)
        switch result.verdict {
        case .match:
            fileMatch += 1; totalMatch += 1
        case .bothError:
            fileMatch += 1; totalBothError += 1 // Both agree it's an error
        case .mismatch:
            fileIssues += 1; totalMismatch += 1; issues.append(result)
        case .swiftOnlyError:
            fileIssues += 1; totalSwiftOnly += 1; issues.append(result)
        case .lanternOnlyError:
            fileIssues += 1; totalLanternOnly += 1; issues.append(result)
        case .swiftTimeout:
            totalTimeout += 1
        case .lanternTimeout:
            fileIssues += 1; totalTimeout += 1; issues.append(result)
        }
    }

    let status = fileIssues == 0 ? "ALL MATCH" : "\(fileMatch)/\(fileMatch + fileIssues)"
    print("\(fileName): \(status)")
}

// Summary
let total = totalMatch + totalBothError + totalMismatch + totalSwiftOnly + totalLanternOnly + totalTimeout
print("\n=== Oracle Results: \(totalMatch + totalBothError)/\(total) match ===")
if totalMismatch > 0 { print("  MISMATCH: \(totalMismatch) (both succeed, different output)") }
if totalSwiftOnly > 0 { print("  SWIFT_ONLY_ERROR: \(totalSwiftOnly) (Swift rejects, Lantern accepts — too permissive)") }
if totalLanternOnly > 0 { print("  LANTERN_ONLY_ERROR: \(totalLanternOnly) (Lantern rejects, Swift accepts — bug)") }
if totalTimeout > 0 { print("  TIMEOUT: \(totalTimeout)") }

// Detail for non-matches
if !issues.isEmpty {
    print("\n=== Issues ===")
    for result in issues {
        print("\n[\(result.verdict.rawValue)] \(result.test.fileName):\(result.test.name)")
        switch result.verdict {
        case .mismatch:
            print("  Swift:   \(result.swiftOutput.prefix(100))")
            print("  Lantern: \(result.lanternOutput.prefix(100))")
        case .swiftOnlyError:
            print("  Swift error: \(result.swiftOutput.prefix(100))")
            print("  Lantern ok:  \(result.lanternOutput.prefix(100))")
        case .lanternOnlyError:
            print("  Swift ok:      \(result.swiftOutput.prefix(100))")
            print("  Lantern error: \(result.lanternOutput.prefix(100))")
        case .lanternTimeout:
            print("  Lantern timed out")
        default:
            break
        }
    }
}

exit(issues.isEmpty ? 0 : 1)
