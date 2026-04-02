# Lantern

An embeddable Swift interpreter with integrated debugging for iOS and macOS. Lantern parses Swift source using [SwiftSyntax](https://github.com/swiftlang/swift-syntax), compiles it to bytecode, and executes it on a stack-based virtual machine with bridging into native Apple frameworks.

## Architecture

```
Swift Source
    │
    ▼
SwiftSyntax Parser ──▶ AST ──▶ Optimizer ──▶ Bytecode Compiler
                                                    │
                                                    ▼
                                              CompiledProgram
                                          (bytecode + constant pool
                                           + source map + debug metadata)
                                                    │
                                                    ▼
                                             Virtual Machine
                                        ┌───────────┴───────────┐
                                        ▼                       ▼
                                 Interpreted Code         Host Bridge
                                                    (Native Swift/SwiftUI)
                                        │
                                        ▼
                                    Debugger
                              (breakpoints, stepping,
                               inspection, evaluation)
```

## Modules

| Module | Purpose |
|--------|---------|
| **LanternVM** | Value types, opcode set, bytecode infrastructure, stack-based execution engine |
| **LanternCompiler** | SwiftSyntax parser, AST nodes, bytecode compiler, AST optimizer (6 passes), IDE support |
| **LanternDebugger** | Breakpoints, stepping, variable inspection/modification, expression evaluation, event log |
| **LanternBridge** | Host function/type registry, type conversion, Foundation bridges |
| **LanternSwiftUI** | ViewStub, state store, observable wrapper, view descriptors |
| **Lantern** | Top-level `Interpreter` facade, REPL, output routing |

## Requirements

- macOS 15+ / iOS 18+
- Swift 6.0+
- SwiftSyntax 600.0.1

## Usage

### Basic Execution

```swift
import Lantern

let interpreter = Interpreter()

let result = interpreter.run(source: """
    func fibonacci(_ n: Int) -> Int {
        if n <= 1 { return n }
        return fibonacci(n - 1) + fibonacci(n - 2)
    }
    print(fibonacci(10))
    """)
```

### Captured Output

```swift
let output = CapturedOutputHandler()
let interpreter = Interpreter()
interpreter.outputHandler = output

interpreter.run(source: """
    for i in 1...5 {
        print("Line \\(i)")
    }
    """)

print(output.printOutput)
// ["Line 1\n", "Line 2\n", "Line 3\n", "Line 4\n", "Line 5\n"]
```

### Custom Bridge Registration

```swift
let bridge = BridgeRegistry.default

bridge.registerFunction("randomInt", parameterLabels: ["in"]) { args in
    guard case .int(let upper) = args[0] else { return .nil_ }
    return .int(Int.random(in: 0..<upper))
}

let interpreter = Interpreter(bridge: bridge)
interpreter.run(source: "print(randomInt(in: 100))")
```

### Debugging

```swift
let interpreter = Interpreter()
let debugger = interpreter.debugger

debugger.addBreakpoint(file: "app.swift", line: 15, condition: nil)
debugger.isBreakOnExceptions = true
debugger.delegate = self

// When paused:
let stack = debugger.callStack()
let vars = debugger.locals(frameIndex: 0)
let result = debugger.evaluate(expression: "items.count", inFrame: 0)
debugger.stepOver()
```

### REPL

```
$ swift run lantern-repl
Lantern REPL — Swift Interpreter
Type Swift expressions or :quit to exit.

lantern> print(3 + 4)
7
lantern> let name = "World"
lantern> print("Hello \(name)")
Hello World
lantern> :quit
```

## Conformance Testing

The `Fixtures/Conformance/` directory contains 351 test cases across 15 fixture files. Each test specifies Swift source and expected output, validated against both the real Swift compiler and the Lantern interpreter.

Validate fixtures against the Swift compiler:

```
swift Fixtures/Conformance/conformance_runner.swift Fixtures/Conformance/
```

Run conformance tests through the interpreter:

```
swift test --filter ConformanceTests
```

## AST Optimizer

The compiler includes six optimization passes that transform the AST before bytecode emission:

1. **Constant Folding** — `2 + 3` becomes `5`
2. **Constant Propagation** — tracks `let` bindings with known values
3. **Algebraic Simplification** — `x + 0` becomes `x`, `x * 1` becomes `x`
4. **Strength Reduction** — `x * 8` becomes `x << 3`
5. **Common Subexpression Elimination** — detects repeated pure expressions
6. **Dead Code Elimination** — removes unreachable branches and code after returns

The optimizer iterates until convergence (up to 3 passes by default).

## Project Status

Lantern is under active development. The interpreter currently handles:

- Integer, double, boolean, string, and nil literals
- Arithmetic, comparison, and logical operators
- `let` and `var` declarations
- `print()` output
- String concatenation
- Global variable storage and retrieval

Upcoming work follows the phased implementation plan, progressively adding control flow, functions, closures, collections, user-defined types, protocols, error handling, and the SwiftUI bridge.

## License

MIT
