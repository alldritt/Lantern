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
| **Lantern** | Top-level facade. Compile and run Swift source in one call. |
| **LanternCompiler** | Parse and compile Swift source to bytecode. |
| **LanternVM** | Execute compiled bytecode. |
| **LanternDebugger** | Breakpoints, stepping, inspection, modification. |
| **LanternBridge** | Register native Swift types and functions for use by interpreted code. |
| **LanternSwiftUI** | SwiftUI view bridge, state management, view descriptors. |

## Requirements

- macOS 15+ / iOS 18+
- Swift 6.0+
- SwiftSyntax 600.0.1

## Quick Start

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

### Basic Execution

```swift
import Lantern

let interpreter = Interpreter()

let result = interpreter.run(source: """
    func fibonacci(_ n: Int) -> Int {
        if n <= 1 { return n }
        return fibonacci(n - 1) + fibonacci(n - 2)
    }
    let answer = fibonacci(10)
    print("Result: \\(answer)")
    """)

switch result {
case .success(let value):
    print("Returned: \(value)")
case .failure(let error):
    print("Error: \(error)")
}
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
// ["Line 1", "Line 2", "Line 3", "Line 4", "Line 5"]
```

### Custom Bridge Registration

```swift
let bridge = BridgeRegistry.default

bridge.registerType("Counter") { args in
    let start = args.first?.intValue ?? 0
    return .hostObject(HostObjectRef(
        object: Counter(startingAt: start),
        typeName: "Counter"
    ))
}

bridge.registerMethod(
    typeName: "Counter",
    selector: "increment",
    parameterLabels: []
) { receiver, args in
    guard let ref = receiver.hostObjectRef,
          let counter = ref.object as? Counter else {
        throw BridgeError.argumentConversionFailed(
            parameter: "self", expected: "Counter", got: receiver.typeName
        )
    }
    counter.increment()
    return .void
}

bridge.registerProperty(
    typeName: "Counter",
    name: "value",
    getter: { receiver in
        guard let ref = receiver.hostObjectRef,
              let counter = ref.object as? Counter else { return .nil_ }
        return .int(counter.value)
    },
    setter: nil
)

let interpreter = Interpreter(bridge: bridge)
interpreter.run(source: """
    let c = Counter(startingAt: 10)
    c.increment()
    c.increment()
    print(c.value)  // 12
    """)
```

### Debugging

```swift
let interpreter = Interpreter()

let program = try interpreter.compile(
    source: mySource,
    fileName: "app.swift"
).get()

let debugger = interpreter.debugger
debugger.delegate = self

// Set a breakpoint
debugger.addBreakpoint(file: "app.swift", line: 15, condition: nil)

// Enable exception breakpoints
debugger.isBreakOnExceptions = true

// Run — execution will pause at line 15
debugger.run()

// ... delegate receives debuggerDidPause ...

// Inspect state
let stack = debugger.callStack()
let vars = debugger.locals(frameIndex: 0)

for v in vars {
    print("\(v.name): \(v.value.debugSummary)")
}

// Evaluate an expression in the current context
let result = debugger.evaluate(
    expression: "items.count > 10",
    inFrame: 0
)

// Modify a variable
debugger.setVariable(
    name: "retryCount",
    value: .int(0),
    inFrame: 0
)

// Continue execution
debugger.stepOver()
```

### REPL Mode (Programmatic)

```swift
let interpreter = Interpreter()

// First input
interpreter.evaluate(expression: "var total = 0")

// Second input — state persists
interpreter.evaluate(expression: "total += 42")

// Third input — reads accumulated state
let result = interpreter.evaluate(expression: "total")
// .success(.int(42))
```

### Syntax Highlighting

```swift
import LanternCompiler

let tokens = classifyTokens(source: """
    let name = "World"
    print("Hello \\(name)")
    """)

for token in tokens {
    print("\(token.text) → \(token.classification)")
}
// let → keyword
// name → identifier
// = → operator
// "World" → stringLiteral
// print → functionName
// ...
```

### SwiftUI View Execution

```swift
import Lantern
import LanternSwiftUI
import SwiftUI

let interpreter = Interpreter()

// Compile a SwiftUI view
let program = try interpreter.compile(source: """
    struct CounterView: View {
        @State var count = 0
        
        var body: some View {
            VStack(spacing: 20) {
                Text("Count: \\(count)")
                    .font(.title)
                Button("Increment") {
                    count += 1
                }
            }
            .padding()
        }
    }
    """, fileName: "CounterView.swift").get()

try interpreter.execute(program: program).get()

// Create a native SwiftUI view from the interpreted definition
let instance = interpreter.createInstance(typeName: "CounterView")
let view = interpreter.makeView(from: instance)

// Use in a SwiftUI hierarchy
struct HostView: View {
    let lanternView: ViewStub
    
    var body: some View {
        lanternView
    }
}
```

### View Descriptor Inspection

```swift
if let descriptor = interpreter.currentViewDescriptor {
    print(descriptor.typeName)              // "VStack"
    print(descriptor.children.count)        // 2
    print(descriptor.children[0].typeName)  // "Text"
    print(descriptor.children[1].typeName)  // "Button"
    
    // Inspect modifiers
    let textModifiers = descriptor.children[0].modifiers
    print(textModifiers[0].name)            // "font"
    
    // Walk the tree
    for child in descriptor.flattened() {
        print("\(child.typeName) at line \(child.sourceLocation.line)")
    }
}
```

-----

## Public API Reference

### Module: Lantern

#### Interpreter

The main entry point. Compiles and executes Swift source, manages the bridge registry, and exposes the debugger.

```swift
public final class Interpreter {

    /// Create an interpreter with an optional bridge registry.
    /// If no registry is provided, a default registry with Foundation
    /// and standard library bridges is used.
    public init(bridge: BridgeRegistry = .default)

    /// The bridge registry for registering host types and functions.
    public var bridge: BridgeRegistry { get }

    /// The debugger interface. Always available — debugging is always on.
    public var debugger: DebuggerInterface { get }

    /// Compile Swift source into a compiled program.
    /// Returns diagnostics on failure.
    public func compile(
        source: String,
        fileName: String = "<input>"
    ) -> Result<CompiledProgram, [CompilerDiagnostic]>

    /// Compile and execute Swift source in one step.
    public func run(
        source: String,
        fileName: String = "<input>"
    ) -> Result<Value, InterpreterError>

    /// Execute a previously compiled program.
    public func execute(
        program: CompiledProgram
    ) -> Result<Value, InterpreterError>

    /// Execute a program, pausing at the first executable statement.
    public func executePaused(
        program: CompiledProgram
    ) -> Result<Value, InterpreterError>

    /// Execute a single expression and return its value.
    /// Useful for REPL-style evaluation.
    public func evaluate(
        expression: String,
        fileName: String = "<expr>"
    ) -> Result<Value, InterpreterError>

    /// Wrap a View-conforming instance in ViewBox for live preview.
    public func wrapViewInstanceIfNeeded(_ value: Value) -> Value

    /// The output handler for print() and debugPrint() calls.
    /// Defaults to stdout.
    public var outputHandler: OutputHandler { get set }

    /// Maximum call stack depth before stack overflow error.
    public var maxCallDepth: Int { get set }

    /// Maximum execution steps before timeout.
    /// Default: nil (no limit).
    public var maxExecutionSteps: Int? { get set }

    /// Reset the interpreter state, clearing all globals and
    /// REPL history. Bridge registrations are preserved.
    public func reset()
}
```

#### OutputHandler

```swift
public protocol OutputHandler {
    func handlePrint(_ text: String)
    func handleDebugPrint(_ text: String)
}

public struct StandardOutputHandler: OutputHandler { ... }
public final class CapturedOutputHandler: OutputHandler {
    public var printOutput: [String] { get }
    public var debugPrintOutput: [String] { get }
    public func clear()
}
```

-----

### Module: LanternCompiler

#### CompiledProgram

```swift
public struct CompiledProgram {
    public let bytecode: [UInt8]
    public let constantPool: ConstantPool
    public let sourceMap: SourceMap
    public let variableTable: [VariableRecord]
    public let functionTable: [FunctionDebugInfo]
    public let typeTable: [TypeDebugInfo]
    public let sourceText: String
    public let fileName: String
}
```

#### FunctionRef

```swift
public struct FunctionRef {
    public let name: String
    public let parameters: [ParameterInfo]
    public let localCount: UInt16
    public let isAsync: Bool
    public let isThrowing: Bool
    public let bytecode: [UInt8]
    public let exceptionHandlers: [ExceptionHandler]
}

public struct ParameterInfo {
    public let label: String?
    public let name: String
    public let typeAnnotation: String?
    public let hasDefault: Bool
}

public struct ExceptionHandler {
    public let tryStart: Int
    public let tryEnd: Int
    public let handlerStart: Int
    public let handlerSlot: UInt16
}
```

#### SourceMap

```swift
public struct SourceMap {
    public let files: [String]
    public func location(forOffset offset: Int) -> SourceLocation?
    public func offsets(forLine line: UInt32, fileIndex: UInt16) -> [Int]
    public func firstExecutableOffset(
        atOrAfterLine line: UInt32, fileIndex: UInt16
    ) -> (offset: Int, line: UInt32)?
}

public struct SourceLocation: Equatable, Hashable, CustomStringConvertible {
    public let fileIndex: UInt16
    public let line: UInt32
    public let column: UInt16
}
```

#### Debug Metadata

```swift
public struct VariableRecord {
    public let name: String
    public let slotIndex: UInt16
    public let scopeStart: Int
    public let scopeEnd: Int
    public let isMutable: Bool
    public let typeAnnotation: String?
}

public struct FunctionDebugInfo {
    public let name: String
    public let parameterNames: [String]
    public let sourceRange: (start: SourceLocation, end: SourceLocation)
    public let bytecodeRange: (start: Int, end: Int)
}

public struct TypeDebugInfo {
    public let name: String
    public let kind: TypeKind
    public let properties: [PropertyInfo]
    public let methods: [String]
    public let conformances: [String]
    public let sourceRange: (start: SourceLocation, end: SourceLocation)
}

public enum TypeKind { case struct, class, enum }

public struct PropertyInfo {
    public let name: String
    public let typeAnnotation: String?
    public let isMutable: Bool
    public let isComputed: Bool
    public let isStatic: Bool
}
```

#### CompilerDiagnostic

```swift
public struct CompilerDiagnostic: Error, CustomStringConvertible {
    public let message: String
    public let location: SourceLocation
    public let severity: DiagnosticSeverity
    public let sourceLine: String?
}

public enum DiagnosticSeverity { case error, warning }
```

#### Syntax Classification

```swift
public struct TokenInfo {
    public let range: (start: SourceLocation, end: SourceLocation)
    public let classification: TokenClassification
    public let text: String
}

public enum TokenClassification {
    case keyword, identifier, typeName, functionName
    case stringLiteral, numberLiteral, boolLiteral
    case comment, operator, punctuation, interpolationAnchor
}

public func classifyTokens(source: String, fileName: String = "<input>") -> [TokenInfo]
```

#### Autocomplete

```swift
public struct CompletionItem {
    public let label: String
    public let detail: String?
    public let kind: CompletionKind
    public let insertText: String
}

public enum CompletionKind {
    case variable, function, method, property, type, keyword, enumCase
}

public func completions(
    source: String, cursorOffset: Int, interpreter: Interpreter
) -> [CompletionItem]
```

-----

### Module: LanternVM

#### Value

The universal runtime value type.

```swift
public enum Value: Equatable, CustomStringConvertible {
    case int(Int)
    case double(Double)
    case bool(Bool)
    case string(String)
    case nil_
    case array([Value])
    case dictionary([String: Value])
    case optional(Value?)
    case closure(ClosureRef)
    case hostObject(HostObjectRef)
    case instance(InstanceRef)
    case enumCase(EnumCaseRef)
    case range(Int, Int, Bool)
    case void

    public var typeName: String { get }
    public var isNil: Bool { get }

    public var intValue: Int? { get }
    public var doubleValue: Double? { get }
    public var boolValue: Bool? { get }
    public var stringValue: String? { get }
    public var arrayValue: [Value]? { get }
    public var dictionaryValue: [String: Value]? { get }

    public var debugSummary: String { get }
    public var debugChildren: [DebugChild]? { get }
    public var description: String { get }
}

public struct DebugChild {
    public let label: String
    public let value: Value
}
```

#### ClosureRef / InstanceRef / EnumCaseRef / HostObjectRef

```swift
public struct ClosureRef {
    public let function: FunctionRef
    public let captures: [Value]
}

public final class InstanceRef {
    public let typeName: String
    public let kind: TypeKind
    public func property(_ name: String) -> Value?
    public var propertyNames: [String] { get }
}

public struct EnumCaseRef: Equatable {
    public let typeName: String
    public let caseName: String
    public let associatedValues: [Value]?
    public let rawValue: Value?
}

public final class HostObjectRef {
    public let object: AnyObject
    public let typeName: String
}
```

#### InterpreterError

```swift
public struct InterpreterError: Error, CustomStringConvertible {
    public let kind: ErrorKind
    public let message: String
    public let location: SourceLocation?
    public let sourceLine: String?
}

public enum ErrorKind {
    case typeMismatch, nilUnwrap, indexOutOfBounds, divisionByZero
    case stackOverflow, undefinedVariable, undefinedFunction
    case undefinedMethod, undefinedProperty, wrongArgumentCount
    case argumentLabelMismatch, immutableAssignment, missingReturn
    case uncaughtThrow, hostBridgeError, executionLimitExceeded
    case custom(String)
}
```

-----

### Module: LanternDebugger

#### DebuggerInterface

```swift
public protocol DebuggerInterface: AnyObject {
    // Execution control
    func run()
    func startPaused()
    func pause()
    func stepOver()
    func stepInto()
    func stepOut()
    func stepToLine(_ line: Int, file: String)
    var isPaused: Bool { get }
    var pausedLocation: SourceLocation? { get }
    var pauseReason: PauseReason? { get }

    // Breakpoints
    @discardableResult func addBreakpoint(file: String, line: Int, condition: String?) -> Breakpoint
    func removeBreakpoint(_ id: UUID)
    func enableBreakpoint(_ id: UUID, enabled: Bool)
    @discardableResult func addWatchpoint(variable: String, inFrame frameIndex: Int?) -> Breakpoint
    @discardableResult func addHostCallBreakpoint(functionName: String, timing: HostCallBreakpointTiming) -> Breakpoint
    var isBreakOnExceptions: Bool { get set }
    var breakpoints: [Breakpoint] { get }

    // Inspection
    var lastExpressionResult: Value? { get }
    func callStack() -> [FrameInfo]
    func locals(frameIndex: Int) -> [VariableInfo]
    func captures(frameIndex: Int) -> [VariableInfo]
    func globals() -> [VariableInfo]
    func evaluate(expression: String, inFrame frameIndex: Int) -> Result<Value, InterpreterError>

    // Modification
    func setVariable(name: String, value: Value, inFrame frameIndex: Int) -> Result<VariableModification, DebuggerError>
    func executeStatement(statement: String, inFrame frameIndex: Int) -> Result<Void, InterpreterError>

    // Event log
    var eventLog: [DebugEvent] { get }
    func clearEventLog()
    var delegate: DebuggerDelegate? { get set }
}
```

#### DebuggerDelegate

```swift
public protocol DebuggerDelegate: AnyObject {
    func debuggerDidPause(at location: SourceLocation, reason: PauseReason)
    func debuggerDidResume()
    func debuggerDidEncounterError(_ error: InterpreterError)
    func debuggerDidProduceOutput(_ text: String)
    func debuggerDidLogEvent(_ event: DebugEvent)
    func debuggerDidComplete(result: Value?)
}
```

#### Breakpoint

```swift
public struct Breakpoint: Identifiable {
    public let id: UUID
    public let kind: BreakpointKind
    public var isEnabled: Bool
    public var condition: String?
    public var hitCount: Int
    public var ignoreCount: Int
    public var resolvedLocation: SourceLocation?
}

public enum BreakpointKind {
    case line(file: String, line: Int)
    case watchpoint(variable: String, frameIndex: Int?)
    case exception
    case hostCall(functionName: String, timing: HostCallBreakpointTiming)
}

public enum HostCallBreakpointTiming { case before, after }
```

#### FrameInfo / VariableInfo

```swift
public struct FrameInfo {
    public let functionName: String
    public let sourceLocation: SourceLocation?
    public let frameIndex: Int
    public let isHostFrame: Bool
    public let arguments: [(label: String?, value: Value)]
}

public struct VariableInfo {
    public let name: String
    public let value: Value
    public let typeName: String
    public let isMutable: Bool
    public let scopeDepth: Int
}

public struct VariableModification {
    public let name: String
    public let oldValue: Value
    public let newValue: Value
    public let wasImmutable: Bool
}
```

#### PauseReason / DebugEvent / DebuggerError

```swift
public enum PauseReason {
    case breakpoint(Breakpoint)
    case step
    case watchpoint(variable: String, oldValue: Value, newValue: Value)
    case exception(InterpreterError)
    case userRequested
}

public enum DebugEvent {
    case breakpointHit(Breakpoint, SourceLocation)
    case watchpointTriggered(variable: String, oldValue: Value, newValue: Value, location: SourceLocation)
    case exceptionRaised(InterpreterError, SourceLocation)
    case hostCallMade(functionName: String, arguments: [Value], location: SourceLocation)
    case hostCallReturned(functionName: String, result: Value)
    case hostCallThrew(functionName: String, error: Error)
    case printOutput(String)
    case stateModified(variable: String, oldValue: Value, newValue: Value, frameIndex: Int)
}

public enum DebuggerError: Error, CustomStringConvertible {
    case notPaused
    case variableNotFound(String)
    case variableOutOfScope(String)
    case typeMismatch(expected: String, got: String)
    case frameIndexOutOfRange(Int)
    case breakpointNotFound(UUID)
    case expressionCompilationFailed([CompilerDiagnostic])
}
```

-----

### Module: LanternBridge

#### BridgeRegistry

```swift
public final class BridgeRegistry {
    public init()
    public static var `default`: BridgeRegistry { get }

    // Type registration
    public func registerType(_ name: String, constructor: @escaping ([Value]) throws -> Value)
    public func registerInitializer(typeName: String, parameterLabels: [String?], initializer: @escaping ([Value]) throws -> Value)

    // Method registration
    public func registerMethod(typeName: String, selector: String, parameterLabels: [String?], method: @escaping (Value, [Value]) throws -> Value)
    public func registerStaticMethod(typeName: String, selector: String, parameterLabels: [String?], method: @escaping ([Value]) throws -> Value)

    // Property registration
    public func registerProperty(typeName: String, name: String, getter: @escaping (Value) throws -> Value, setter: ((Value, Value) throws -> Void)?)
    public func registerStaticProperty(typeName: String, name: String, getter: @escaping () throws -> Value, setter: ((Value) throws -> Void)?)

    // Free functions
    public func registerFunction(_ name: String, parameterLabels: [String?], function: @escaping ([Value]) throws -> Value)

    // Async
    public func registerAsyncMethod(typeName: String, selector: String, parameterLabels: [String?], method: @escaping (Value, [Value]) async throws -> Value)
    public func registerAsyncFunction(_ name: String, parameterLabels: [String?], function: @escaping ([Value]) async throws -> Value)

    // Debug display
    public func registerDebugDisplay(typeName: String, summary: @escaping (Value) -> String, children: @escaping (Value) -> [DebugChild]?)

    // Queries
    public func isTypeRegistered(_ name: String) -> Bool
    public func isMethodRegistered(typeName: String, selector: String) -> Bool
    public var registeredTypes: [String] { get }
    public func registeredMethods(forType name: String) -> [String]
    public func registeredProperties(forType name: String) -> [String]
    public var registeredFunctions: [String] { get }

    // Host call observer
    public var hostCallObserver: HostCallObserver? { get set }
}
```

#### HostCallObserver / BridgeConvertible / BridgeError

```swift
public protocol HostCallObserver: AnyObject {
    func willCallHost(functionName: String, arguments: [Value], location: SourceLocation?)
    func didReturnFromHost(functionName: String, result: Value)
    func didThrowFromHost(functionName: String, error: Error)
}

public protocol BridgeConvertible {
    static func fromInterpreterValue(_ value: Value) -> Self?
    func toInterpreterValue() -> Value
}
// Built-in: Int, Double, Bool, String, Array, Dictionary, Optional, Date, URL, Data, UUID

public enum BridgeError: Error, CustomStringConvertible {
    case typeNotRegistered(String)
    case methodNotRegistered(typeName: String, selector: String)
    case propertyNotRegistered(typeName: String, name: String)
    case functionNotRegistered(String)
    case argumentConversionFailed(parameter: String, expected: String, got: String)
    case returnConversionFailed(typeName: String)
    case readOnlyProperty(typeName: String, name: String)
    case duplicateRegistration(String)
}
```

-----

### Module: LanternSwiftUI

#### ViewStub

```swift
public struct ViewStub: View {
    public init(vm: VM, instance: InstanceRef, stateStore: LanternStateStore, appStorageKeys: [String: String])
    public var lastDescriptor: ViewDescriptor? { get }
    public var body: some View { get }
}
```

#### LanternStateStore

```swift
public final class LanternStateStore: ObservableObject {
    public func get(_ name: String) -> Value
    public func set(_ name: String, _ value: Value)
    public func contains(_ name: String) -> Bool
    public var allKeys: [String] { get }
    public var snapshot: [String: Value] { get }
}
```

#### LanternObservableWrapper

```swift
public final class LanternObservableWrapper: ObservableObject {
    public init(interpreter: Interpreter, instance: InstanceRef)
    public var instance: InstanceRef { get }
    public func propertyDidChange(_ name: String)
}
```

#### ViewDescriptor / ModifierDescriptor

```swift
public struct ViewDescriptor {
    public let typeName: String
    public let properties: [String: Value]
    public let modifiers: [ModifierDescriptor]
    public let children: [ViewDescriptor]
    public let sourceLocation: SourceLocation
    public var totalViewCount: Int { get }
    public func flattened() -> [ViewDescriptor]
    public func descriptor(at location: SourceLocation) -> ViewDescriptor?
}

public struct ModifierDescriptor {
    public let name: String
    public let arguments: [String: Value]
    public let sourceLocation: SourceLocation
}
```

#### ViewDescriptorBuilder / ViewCollector

```swift
public final class ViewDescriptorBuilder {
    public func beginView(typeName: String, properties: [String: Value], location: SourceLocation)
    public func addModifier(_ modifier: ModifierDescriptor)
    public func endView()
    public var rootDescriptor: ViewDescriptor? { get }
    public func reset()
}

public final class ViewCollector {
    public func add(_ view: AnyView, descriptor: ViewDescriptor)
    public var views: [AnyView] { get }
    public var descriptors: [ViewDescriptor] { get }
    public var count: Int { get }
    public var isEmpty: Bool { get }
    public func clear()
}
```

#### Interpreter SwiftUI Extensions

```swift
extension Interpreter {
    public func createInstance(typeName: String, arguments: [Value]) -> InstanceRef?
    public func makeView(from instance: InstanceRef) -> ViewStub
    public func wrapViewInstanceIfNeeded(_ value: Value) -> Value
    public var currentViewDescriptor: ViewDescriptor? { get }
}
```

-----

## Conformance Testing

The `Fixtures/Conformance/` directory contains 460+ test cases across 20 fixture files covering arithmetic, strings, control flow, functions, closures, arrays, dictionaries, optionals, structs, classes, enums, protocols, error handling, higher-order functions, complex programs, let assignment, negative tests, compile errors, SwiftUI views, and core type methods.

Each test specifies Swift source and expected output, validated against both the real Swift compiler and the Lantern interpreter. The test format supports:

- `// EXPECT: output` — exact output match
- `// EXPECT: ERROR` — any compile or runtime error expected
- `// EXPECT: ERROR@3` — error expected at specific line
- `// EXPECT: VIEW` — ViewBox result (SwiftUI)
- `// EXPECT: COMPILES` — no errors, no output check

### Swift Oracle

Compare Lantern output against the real Swift compiler for every test:

```
swift run lantern-conformance Fixtures/Conformance/
```

Reports: `MATCH`, `MISMATCH`, `SWIFT_ONLY_ERROR` (too permissive), `LANTERN_ONLY_ERROR` (bug).

### Run Tests

```
swift test --filter Conformance       # all fixtures as individual @Test cases
swift test --filter runAllConformance # summary report
swift test                            # full 570+ test suite
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

## SwiftUI Bridge Guide

The SwiftUI bridge connects interpreted Swift view definitions to native SwiftUI rendering. Interpreted code writes real Swift — `Text("Hello")`, `VStack { ... }`, `Button("Tap") { ... }` — and the bridge constructs real SwiftUI views at runtime.

### How It Works

```
Interpreted Swift source
    │
    ▼
Compiler (detects View conformance, @State properties)
    │  emits stateGet/stateSet opcodes for @State
    │  emits normal bytecode for body computed property
    ▼
CompiledProgram
    │
    ▼
Interpreter.execute(program:)
    │  registers type constructors (Text, VStack, Button, ...)
    │  via BridgeRegistry → VM globals
    ▼
Interpreter.createInstance(typeName: "MyView")
    │  creates an InstanceRef for the view struct
    ▼
Interpreter.makeView(from: instance) → ViewStub
    │  ViewStub is a native SwiftUI View
    │  its body calls vm.invokeValue(getter, args: [self])
    │  which evaluates the interpreted body computed property
    │  returning AnyView trees built from bridge-registered types
    ▼
Native SwiftUI rendering
```

### Step-by-Step Usage

**1. Define an interpreted view**

```swift
let source = """
struct GreetingView: View {
    var body: some View {
        VStack {
            Text("Hello from Lantern!")
                .font(.title)
                .padding()
            Text("This view is interpreted")
                .foregroundColor(.gray)
        }
    }
}
"""
```

**2. Compile and execute**

```swift
import Lantern
import LanternSwiftUI

let interpreter = Interpreter()

// Compile the source — this parses, compiles to bytecode, and
// registers the struct type with its body computed property
let program = try interpreter.compile(source: source).get()

// Execute the program — this runs top-level code and registers
// type constructors (Text, VStack, etc.) in the VM environment
try interpreter.execute(program: program).get()
```

**3. Create an instance and wrap in ViewStub**

```swift
// Create an interpreted instance of the view struct
guard let instance = interpreter.createInstance(typeName: "GreetingView") else {
    fatalError("GreetingView not found in compiled program")
}

// Wrap in a native SwiftUI view
let lanternView = interpreter.makeView(from: instance)
```

**4. Embed in your SwiftUI hierarchy**

```swift
struct ContentView: View {
    let lanternView: ViewStub

    var body: some View {
        NavigationStack {
            lanternView
                .navigationTitle("Lantern Preview")
        }
    }
}
```

### @State and Reactivity

When the compiler detects `@State` properties in a View struct, it emits `stateGet` and `stateSet` opcodes instead of normal property access. At runtime, these read and write through a `LanternStateStore` owned by the `Interpreter` (keyed by instance identity, so it survives view recreation). A `StateObserver` bridges store changes to SwiftUI's observation system.

```swift
let source = """
struct CounterView: View {
    @State var count = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("Count: \\(count)")
                .font(.largeTitle)
            Button("Increment") {
                count = count + 1
            }
        }
        .padding()
    }
}
"""
```

The flow for a button tap:
1. SwiftUI calls the native closure registered by the Button bridge
2. The closure restores the captured `SwiftUIContext` and calls `vm.invokeValue(actionClosure, args: [])`
3. The closure body executes `count = count + 1` — `stateGet` reads current value, `stateSet` writes new value
4. `stateSet` writes to `LanternStateStore.values["count"]`
5. `@Published` fires `objectWillChange`, which the `StateObserver` forwards to SwiftUI
6. SwiftUI re-evaluates `ViewStub.body`, which re-invokes the interpreted `body` getter
7. The new `count` value is read via `stateGet`, producing updated `Text`

The same context capture mechanism works for `onAppear`, `onTapGesture`, and all lifecycle closures.

### Supported View Types

| Type | Constructor | Notes |
|------|------------|-------|
| `Text` | `Text("string")` | String interpolation with `specifier:` format support |
| `Button` | `Button("title") { action }` | Title + closure, or two closures (action + label) |
| `VStack` | `VStack { ... }` | Optional `spacing:` argument |
| `HStack` | `HStack { ... }` | Optional `spacing:` argument |
| `ZStack` | `ZStack { ... }` | |
| `ScrollView` | `ScrollView { ... }` | |
| `List` | `List { ... }` | |
| `NavigationStack` | `NavigationStack { ... }` | |
| `Form` | `Form { ... }` | |
| `Section` | `Section("header") { ... }` | |
| `Group` | `Group { ... }` | |
| `ForEach` | `ForEach(array) { item in ... }` | |
| `NavigationLink` | `NavigationLink("title") { ... }` | |
| `TabView` | `TabView { ... }` | |
| `Menu` | `Menu("title") { ... }` | |
| `Grid` | `Grid { ... }` | |
| `GeometryReader` | `GeometryReader { proxy in ... }` | |
| `Spacer` | `Spacer()` | |
| `Divider` | `Divider()` | |
| `Image` | `Image("star.fill")` | SF Symbols with `.resizable()`, `.scaledToFit()`, `.imageScale()` |
| `Label` | `Label("title", "star")` | Title + system image |
| `ProgressView` | `ProgressView()` | Optional value |
| `Color` | `Color.red` / `Color(r, g, b)` | Named colors + RGB |
| `Toggle` | `Toggle("label", $binding)` | |
| `TextField` | `TextField("placeholder", $binding)` | |
| `TextEditor` | `TextEditor($binding)` | |
| `Slider` | `Slider($binding)` | |
| `Picker` | `Picker("label")` | |
| `DatePicker` | `DatePicker("label")` | |
| `Stepper` | `Stepper("label")` | |
| `Link` | `Link("title", "url")` | |
| `Circle` | `Circle()` | `.fill(.red)`, `.stroke(.blue, 2)` |
| `Rectangle` | `Rectangle()` | `.fill(.green)` |
| `RoundedRectangle` | `RoundedRectangle(12)` | Corner radius argument |
| `Capsule` | `Capsule()` | |
| `Ellipse` | `Ellipse()` | |

### Supported Modifiers

All modifiers accept Swift-idiomatic enum syntax (`.red`, `.title`, `.center`) as well as string arguments for backward compatibility.

**Layout:** `.padding()`, `.padding(.top, 10)`, `.padding(.horizontal)`, `.frame(width:height:)`, `.offset(x, y)`, `.position(x, y)`, `.fixedSize()`, `.ignoresSafeArea()`, `.zIndex(n)`

**Typography:** `.font(.title)`, `.fontWeight(.bold)`, `.fontDesign(.rounded)`, `.monospaced()`, `.bold()`, `.italic()`, `.underline()`, `.strikethrough()`, `.kerning(n)`, `.tracking(n)`, `.baselineOffset(n)`, `.lineLimit(n)`, `.lineSpacing(n)`, `.multilineTextAlignment(.center)`, `.textCase(.uppercase)`, `.minimumScaleFactor(n)`, `.truncationMode(.tail)`

**Appearance:** `.foregroundColor(.red)`, `.foregroundStyle(.blue)`, `.background(.green)`, `.overlay(.red)` (color or view), `.opacity(0.5)`, `.cornerRadius(10)`, `.shadow(radius: 5)`, `.border(.black, 1)`, `.hidden()`, `.blur(radius: 5)`, `.clipShape(.circle)`, `.tint(.orange)`, `.fill(.red)`, `.stroke(.blue, 2)`

**Image:** `.resizable()`, `.scaledToFit()`, `.scaledToFill()`, `.aspectRatio(.fit)`, `.imageScale(.large)`, `.renderingMode(.template)`, `.symbolRenderingMode(.multicolor)`

**Transforms:** `.rotationEffect(degrees)`, `.scaleEffect(scale)`

**Interaction:** `.disabled(true)`, `.allowsHitTesting(false)`, `.contentShape()`

**Navigation:** `.navigationTitle("Title")`

**Styling:** `.listStyle(.plain)`

**Lifecycle:** `.onAppear { }`, `.onDisappear { }`, `.onTapGesture { }`, `.onChange { }`, `.task { }`

**Animation:** `.animation(.easeIn)`, `.transition(.slide)`, `.contentTransition(.opacity)`, `.symbolEffect(.bounce)`

### Architecture

The bridge uses three layers:

1. **BridgeRegistry** — Single source of truth for all SwiftUI type constructors and modifier methods. Populated by `registerSwiftUIBridge(on:vm:)` during Interpreter init.

2. **VM Dispatch** — When interpreted code calls `Text("Hello")`, the compiler emits a `CALL` opcode. The VM finds `Text` as a `NativeFunctionRef` global (registered from the bridge). The native function creates an `AnyView(Text("Hello"))` wrapped in a `ViewBox` inside a `HostObjectRef`. Modifier calls like `.padding()` dispatch through `callMethod` → bridge lookup → `ModifierApplicator`.

3. **ViewStub** — A native `SwiftUI.View` that evaluates the interpreted `body` computed property on each render. It manages `@State` through `LanternStateStore` and converts the returned `Value` (containing `HostObjectRef(ViewBox)`) back to `AnyView`.

### SwiftUI Limitations

- **No `sheet`/`alert`/`fullScreenCover`** — presentation modifiers not yet implemented
- **No `@ViewBuilder` conditionals** — `if`/`else` in view builders doesn't yet produce conditional SwiftUI content (works in closures via runtime branching)
- **`.resizable()` limitation** — Image-specific modifiers that require `Image` type (not `AnyView`) have reduced effect due to type erasure
- **Simplified `Picker`/`DatePicker`** — generic selection bindings not fully supported
- **View descriptor tree** — `currentViewDescriptor` is not yet populated during evaluation

## Language Limitations

Features parsed by SwiftSyntax but not yet fully implemented in the interpreter:

### Concurrency
- **`async`/`await`** — keywords are parsed and `await` compiles (as a no-op pass-through), but there is no async execution runtime; `async` functions execute synchronously
- **`actor`** — not implemented; no actor isolation or message passing
- **Structured concurrency** — `Task { }`, `TaskGroup`, `async let` not implemented
- **`Sendable`** — no compile-time sendability checking

### Type System
- **Generics** — `<T>` type parameters are stripped during parsing (`Stack<Int>` becomes `Stack`); no generic specialization, type constraints, or where clauses on generics
- **Opaque types** — `some View` is recognized for View conformance detection but there is no opaque type enforcement
- **Existential types** — `any Protocol` not supported
- **Type inference** — minimal; no expression-level type inference for overload resolution or generic parameter deduction

### Classes & Inheritance
- **Class inheritance** — `superclass` is parsed and stored but `super.init()`, `super.method()`, and method override resolution are not implemented
- **`override` keyword** — recognized but not enforced or dispatched
- **`deinit`** — not implemented; no deterministic deinitialization
- **ARC** — no reference counting; class instances are never deallocated

### Protocols
- **Protocol requirements** — conformance is declared and tracked but protocol requirement satisfaction is not verified at compile time
- **Associated types** — not implemented
- **Protocol witnesses** — no witness table; method dispatch uses name-based lookup, not protocol conformance dispatch
- **`some`/`any` protocol types** — not enforced

### Property Wrappers
- **`@State`/`@Binding`/`@Published`/`@Environment`/`@ObservedObject`/`@AppStorage`** — implemented for SwiftUI via special opcodes
- **Custom property wrappers** — `@propertyWrapper` not supported; only the built-in set above

### Other Missing Features
- **`subscript` declarations** — user-defined subscript operators not supported (array/dictionary subscripts are built-in)
- **Operator overloading** — custom operator declarations not supported
- **Access control** — `public`/`private`/`internal`/`fileprivate` parsed but not enforced
- **`lazy` properties** — not implemented
- **`willSet`/`didSet`** property observers — not implemented (except `@Published` which uses a special opcode)
- **Regex literals** — not supported
- **Macros** — not supported
- **C/Objective-C interop** — not applicable
- **String index model** — strings use integer indices, not Swift's `String.Index`
- **`KeyPath`** — not implemented
- **Variadic generics / parameter packs** — not implemented

## Project Status

**Conformance: 455/460 tests passing (98.9%)** — 18 of 20 fixture files at 100%. Validated against the real Swift compiler via the oracle tool.

**Test suite: 572 tests** across 68 suites — conformance fixtures, SwiftUI runtime tests, closure state mutations, debugger tests, syntax error detection.

The interpreter handles:

- Arithmetic, comparison, logical, bitwise, and string operators with correct precedence
- `let`/`var` declarations (including deferred init), `if`/`else`/`guard`, `while`/`while let`, `for-in` (ranges, arrays, dictionaries)
- Functions with recursion, default parameters, closures with `$0` shorthand, capture lists (`[x]`), and mutable capture sharing
- Arrays with `map`, `filter`, `reduce`, `flatMap`, `compactMap`, `sorted`, `contains`, `enumerated`, `prefix`, `suffix`, `allSatisfy`, `insert`, `removeAll`, `shuffle`, `randomElement`, `firstIndex`, `swapAt`
- Dictionaries with subscript read/write, default subscript, iteration, `sorted`, `compactMapValues`, `mapValues`, `filter`, `merge`, `removeAll`, `forEach`
- Optionals with `if let`, `guard let`, `while let`, nil coalescing (`??`), optional chaining, `map`/`flatMap`, pattern matching
- Structs with memberwise init, custom init, methods, computed properties (get/set), static members, value semantics; compile-time detection of undefined property access
- Classes with custom init, methods, computed properties, reference semantics, static members
- Enums with switch matching (range patterns, where clauses, tuple patterns, associated value destructuring), raw values (Int/String), computed properties, methods
- Protocols with conformance, protocol extension default methods, extensions on built-in types (Int, String, etc.)
- Error handling with `do`/`try`/`catch`, `throw`, `try?`/`try!`, `defer` (LIFO ordering)
- Higher-order functions: `map`, `filter`, `reduce`, `zip`, operator function references (`+`, `*`)
- Tuple expressions, destructuring in `let`/`for-in`, implicit member access (`.title`, `.red`, `.easeIn`)
- String interpolation with format specifiers: `"\(value, specifier: "%.2f")"`, escape sequences, `CustomStringConvertible`
- Core type methods: `Int.random(in:)`, `Double.pi`, `Bool.random()`, `isMultiple(of:)`, `rounded()`, `squareRoot()`, `isNaN`/`isInfinite`/`isZero`
- `print()`, `String()`, `Int()`, `Double()`, `abs()`, `min()`, `max()`, `Array()`, `zip()`, `type(of:)`, `Result`
- Int-to-Double parameter coercion, generic specialization stripping (`Stack<Int>` works)
- Comprehensive syntax error detection via SwiftSyntax's ParseDiagnosticsGenerator

Remaining known issues: 5 tests (optional output format, struct static property overflow, execution limit on complex programs, nested array mutation, use-before-init detection).

## Related Projects

- **[LanternKit](https://github.com/alldritt/LanternKit)** — A library of SwiftUI views and controllers for building Lantern development tools. Provides a source editor, console, live SwiftUI preview, debug panels, and a Code Bubbles-style visual debugger as independent, composable components.

- **[Wick](https://github.com/alldritt/Wick)** — A Swift playground IDE built on Lantern and LanternKit. Write, run, and debug Lantern scripts with live SwiftUI preview, breakpoints, stepping, and variable inspection.

## License

MIT
