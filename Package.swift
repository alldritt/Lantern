// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Lantern",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "Lantern", targets: ["Lantern"]),
        .library(name: "LanternVM", targets: ["LanternVM"]),
        .library(name: "LanternCompiler", targets: ["LanternCompiler"]),
        .library(name: "LanternDebugger", targets: ["LanternDebugger"]),
        .library(name: "LanternBridge", targets: ["LanternBridge"]),
        .library(name: "LanternSwiftUI", targets: ["LanternSwiftUI"]),
        .executable(name: "lantern-repl", targets: ["lantern-repl"]),
        .executable(name: "lantern-bridge-gen", targets: ["lantern-bridge-gen"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "600.0.1"),
    ],
    targets: [
        // MARK: - VM (zero dependencies)
        .target(
            name: "LanternVM",
            path: "Sources/LanternVM"
        ),

        // MARK: - Compiler (→ LanternVM + SwiftSyntax)
        .target(
            name: "LanternCompiler",
            dependencies: [
                "LanternVM",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
            ],
            path: "Sources/LanternCompiler"
        ),

        // MARK: - Debugger (→ LanternVM + LanternCompiler)
        .target(
            name: "LanternDebugger",
            dependencies: ["LanternVM", "LanternCompiler"],
            path: "Sources/LanternDebugger"
        ),

        // MARK: - Bridge (→ LanternVM)
        .target(
            name: "LanternBridge",
            dependencies: ["LanternVM"],
            path: "Sources/LanternBridge"
        ),

        // MARK: - SwiftUI Bridge (→ LanternVM + LanternBridge)
        .target(
            name: "LanternSwiftUI",
            dependencies: ["LanternVM", "LanternBridge"],
            path: "Sources/LanternSwiftUI"
        ),

        // MARK: - Facade (→ all)
        .target(
            name: "Lantern",
            dependencies: [
                "LanternVM",
                "LanternCompiler",
                "LanternDebugger",
                "LanternBridge",
                "LanternSwiftUI",
            ],
            path: "Sources/Lantern"
        ),

        // MARK: - REPL Executable
        .executableTarget(
            name: "lantern-repl",
            dependencies: ["Lantern"],
            path: "Sources/lantern-repl"
        ),

        // MARK: - Bridge Generator
        .executableTarget(
            name: "lantern-bridge-gen",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                "LanternVM",
                "LanternBridge",
            ],
            path: "Sources/lantern-bridge-gen"
        ),

        // MARK: - Tests
        .testTarget(name: "LanternVMTests", dependencies: ["LanternVM"]),
        .testTarget(name: "LanternCompilerTests", dependencies: ["LanternCompiler", "LanternVM"]),
        .testTarget(name: "LanternDebuggerTests", dependencies: ["LanternDebugger", "LanternVM"]),
        .testTarget(name: "LanternBridgeTests", dependencies: ["LanternBridge", "LanternVM"]),
        .testTarget(name: "LanternSwiftUITests", dependencies: ["LanternSwiftUI", "LanternVM", "LanternBridge"]),
        .testTarget(name: "LanternTests", dependencies: ["Lantern"]),
    ]
)
