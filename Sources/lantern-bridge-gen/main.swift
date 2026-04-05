import Foundation

// MARK: - Bridge Generator CLI
//
// Usage:
//   lantern-bridge-gen <framework-name> [--allowlist <file.json>] [--output <file.swift>]
//   lantern-bridge-gen --scan <interface-file>     # Just list all public types
//
// Examples:
//   lantern-bridge-gen --scan /path/to/Charts.swiftinterface
//   lantern-bridge-gen Charts --allowlist charts-allowlist.json --output ChartsBridge.swift

let args = CommandLine.arguments

if args.count < 2 {
    printUsage()
    exit(1)
}

if args[1] == "--scan" {
    // Scan mode: list all public types from the interface file
    guard args.count >= 3 else {
        print("Error: --scan requires a path to a .swiftinterface file")
        exit(1)
    }
    let interfacePath = args[2]
    let types = BridgeGenerator.parse(interfaceFile: interfacePath)

    print("Found \(types.count) public types:\n")
    for type in types.sorted(by: { $0.name < $1.name }) {
        let initCount = type.initializers.count
        let methodCount = type.methods.count + type.staticMethods.count
        let propCount = type.properties.count + type.staticProperties.count
        print("  \(type.kind) \(type.name) — \(initCount) inits, \(methodCount) methods, \(propCount) properties")

        for ini in type.initializers {
            let params = ini.parameters.map { "\($0.label ?? "_"): \($0.type)" }.joined(separator: ", ")
            print("    init(\(params))")
        }
        for m in type.methods.prefix(5) {
            let params = m.parameters.map { "\($0.label ?? "_"): \($0.type)" }.joined(separator: ", ")
            let ret = m.returnType.map { " -> \($0)" } ?? ""
            print("    func \(m.name)(\(params))\(ret)")
        }
        if type.methods.count > 5 {
            print("    ... and \(type.methods.count - 5) more methods")
        }
        for p in type.properties.prefix(5) {
            let access = p.hasSetter ? "{ get set }" : "{ get }"
            print("    var \(p.name): \(p.type) \(access)")
        }
        if type.properties.count > 5 {
            print("    ... and \(type.properties.count - 5) more properties")
        }
    }
    exit(0)
}

// Generate mode
let frameworkName = args[1]
var allowlistPath: String?
var outputPath: String?

var i = 2
while i < args.count {
    if args[i] == "--allowlist" && i + 1 < args.count {
        allowlistPath = args[i + 1]; i += 2
    } else if args[i] == "--output" && i + 1 < args.count {
        outputPath = args[i + 1]; i += 2
    } else {
        i += 1
    }
}

// Find the .swiftinterface file
let sdkPath = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
let frameworkPath = "\(sdkPath)/System/Library/Frameworks/\(frameworkName).framework/Modules/\(frameworkName).swiftmodule"

// Try to find an arm64 interface file
let fm = FileManager.default
var interfacePath: String?
if let contents = try? fm.contentsOfDirectory(atPath: frameworkPath) {
    interfacePath = contents.first(where: { $0.hasSuffix(".swiftinterface") && $0.contains("arm64") })
        .map { "\(frameworkPath)/\($0)" }
}

guard let interfacePath else {
    print("Error: Cannot find .swiftinterface for \(frameworkName)")
    print("Searched in: \(frameworkPath)")
    exit(1)
}

print("Parsing: \(interfacePath)")
var types = BridgeGenerator.parse(interfaceFile: interfacePath)
print("Found \(types.count) public types")

// Apply allowlist if provided
if let allowlistPath {
    guard let data = fm.contents(atPath: allowlistPath),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String]?] else {
        print("Error: Cannot read allowlist at \(allowlistPath)")
        exit(1)
    }
    types = BridgeGenerator.filter(types: types, allowlist: json)
    print("After filtering: \(types.count) types")
}

let output = BridgeGenerator.generateRegistration(types: types, frameworkName: frameworkName)

if let outputPath {
    try? output.write(toFile: outputPath, atomically: true, encoding: .utf8)
    print("Generated: \(outputPath)")
} else {
    print(output)
}

// MARK: - Usage

func printUsage() {
    print("""
    Lantern Bridge Generator

    Parses .swiftinterface files and generates BridgeRegistry registration code.

    Usage:
      lantern-bridge-gen --scan <path.swiftinterface>
        List all public types, methods, and properties.

      lantern-bridge-gen <FrameworkName> [options]
        Generate bridge registration code.

    Options:
      --allowlist <file.json>   Filter to allowed types/methods
      --output <file.swift>     Write to file (default: stdout)

    Allowlist JSON format:
      {
        "TypeName": ["method1", "method2", "propertyName"],
        "OtherType": null   // null = include all public API
      }

    Example:
      lantern-bridge-gen Charts --allowlist charts-allow.json --output ChartsBridge.swift
    """)
}
