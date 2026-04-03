import LanternVM
import LanternCompiler
import LanternDebugger
import LanternBridge

/// The main entry point for the Lantern interpreter.
/// Compiles and executes Swift source, manages the bridge registry,
/// and exposes the debugger.
public final class Interpreter {
    private let vm: VM
    private let compiler: BytecodeCompiler
    private let _debugger: Debugger

    /// The bridge registry for registering host types and functions.
    public let bridge: BridgeRegistry

    /// The debugger interface. Always available — debugging is always on.
    public var debugger: DebuggerInterface { _debugger }

    /// The output handler for print() and debugPrint() calls.
    public var outputHandler: OutputHandler = StandardOutputHandler()

    /// Maximum call stack depth before stack overflow error.
    public var maxCallDepth: Int = 1024

    /// Maximum execution steps before timeout. Nil means no limit.
    public var maxExecutionSteps: Int? = nil

    /// Create an interpreter with an optional bridge registry.
    public init(bridge: BridgeRegistry = .default) {
        self.bridge = bridge
        self.vm = VM(maxCallDepth: 1024)
        self.compiler = BytecodeCompiler()
        self._debugger = Debugger(vm: vm, compiler: compiler)
        registerBuiltins()
    }

    /// Register built-in functions (print, etc.) in the VM environment.
    private func registerBuiltins() {
        // print — variadic, joins with space, appends newline
        let printFn = NativeFunctionRef(name: "print", arity: -1) { [weak self] args in
            let text = args.map { $0.description }.joined(separator: " ")
            self?.outputHandler.handlePrint(text + "\n")
            self?.vm.delegate?.vm(self!.vm, didProduceOutput: text + "\n")
            return .void
        }
        vm.environment.setGlobal("print", value: .nativeFunction(printFn))

        // debugPrint
        let debugPrintFn = NativeFunctionRef(name: "debugPrint", arity: -1) { [weak self] args in
            let text = args.map { $0.debugSummary }.joined(separator: " ")
            self?.outputHandler.handleDebugPrint(text + "\n")
            return .void
        }
        vm.environment.setGlobal("debugPrint", value: .nativeFunction(debugPrintFn))

        // String() — convert value to string
        let stringFn = NativeFunctionRef(name: "String", arity: 1) { args in
            guard let arg = args.first else { return .string("") }
            switch arg {
            case .string(let s): return .string(s)
            case .int(let i): return .string(String(i))
            case .double(let d): return .string(String(d))
            case .bool(let b): return .string(String(b))
            default: return .string(arg.description)
            }
        }
        vm.environment.setGlobal("String", value: .nativeFunction(stringFn))

        // Int() — convert value to int
        let intFn = NativeFunctionRef(name: "Int", arity: 1) { args in
            guard let arg = args.first else { return .nil_ }
            switch arg {
            case .int(let i): return .int(i)
            case .double(let d): return .int(Int(d))
            case .string(let s): return s.isEmpty ? .nil_ : (Int(s).map { .int($0) } ?? .nil_)
            default: return .nil_
            }
        }
        vm.environment.setGlobal("Int", value: .nativeFunction(intFn))

        // Double() — convert value to double
        let doubleFn = NativeFunctionRef(name: "Double", arity: 1) { args in
            guard let arg = args.first else { return .nil_ }
            switch arg {
            case .double(let d): return .double(d)
            case .int(let i): return .double(Double(i))
            case .string(let s): return Double(s).map { .double($0) } ?? .nil_
            default: return .nil_
            }
        }
        vm.environment.setGlobal("Double", value: .nativeFunction(doubleFn))

        // abs()
        let absFn = NativeFunctionRef(name: "abs", arity: 1) { args in
            guard let arg = args.first else { return .nil_ }
            switch arg {
            case .int(let i): return .int(abs(i))
            case .double(let d): return .double(abs(d))
            default: return arg
            }
        }
        vm.environment.setGlobal("abs", value: .nativeFunction(absFn))

        // min/max
        let minFn = NativeFunctionRef(name: "min", arity: -1) { args in
            guard args.count >= 2 else { return args.first ?? .nil_ }
            if let a = args[0].intValue, let b = args[1].intValue { return .int(Swift.min(a, b)) }
            if let a = args[0].doubleValue, let b = args[1].doubleValue { return .double(Swift.min(a, b)) }
            return args[0]
        }
        vm.environment.setGlobal("min", value: .nativeFunction(minFn))

        let maxFn = NativeFunctionRef(name: "max", arity: -1) { args in
            guard args.count >= 2 else { return args.first ?? .nil_ }
            if let a = args[0].intValue, let b = args[1].intValue { return .int(Swift.max(a, b)) }
            if let a = args[0].doubleValue, let b = args[1].doubleValue { return .double(Swift.max(a, b)) }
            return args[0]
        }
        vm.environment.setGlobal("max", value: .nativeFunction(maxFn))

        // Array() — convert to array
        let arrayFn = NativeFunctionRef(name: "Array", arity: 1) { args in
            guard let arg = args.first else { return .array([]) }
            if case .array(let a) = arg { return .array(a) }
            if case .string(let s) = arg { return .array(s.map { .string(String($0)) }) }
            return .array([arg])
        }
        vm.environment.setGlobal("Array", value: .nativeFunction(arrayFn))

        // type(of:) — return type name
        let typeOfFn = NativeFunctionRef(name: "type", arity: 1) { args in
            guard let arg = args.first else { return .string("Void") }
            return .string(arg.typeName)
        }
        vm.environment.setGlobal("type", value: .nativeFunction(typeOfFn))

        // Operator functions as values (for reduce(0, +) etc.)
        let addOpFn = NativeFunctionRef(name: "+", arity: 2) { args in
            let a = args[0], b = args[1]
            if let la = a.intValue, let lb = b.intValue { return .int(la + lb) }
            if let la = a.doubleValue, let lb = b.doubleValue { return .double(la + lb) }
            if case .string(let la) = a, case .string(let lb) = b { return .string(la + lb) }
            return .nil_
        }
        vm.environment.setGlobal("+", value: .nativeFunction(addOpFn))

        let mulOpFn = NativeFunctionRef(name: "*", arity: 2) { args in
            if let a = args[0].intValue, let b = args[1].intValue { return .int(a * b) }
            if let a = args[0].doubleValue, let b = args[1].doubleValue { return .double(a * b) }
            return .nil_
        }
        vm.environment.setGlobal("*", value: .nativeFunction(mulOpFn))
    }

    /// Compile Swift source into a compiled program.
    public func compile(
        source: String,
        fileName: String = "<input>"
    ) -> Result<CompiledProgram, CompilerDiagnostics> {
        compiler.compile(source: source, fileName: fileName)
    }

    /// Compile and execute Swift source in one step.
    @discardableResult
    public func run(
        source: String,
        fileName: String = "<input>"
    ) -> Result<Value, InterpreterError> {
        switch compile(source: source, fileName: fileName) {
        case .success(let program):
            return execute(program: program)
        case .failure(let diags):
            let msg = diags.diagnostics.map { (d: CompilerDiagnostic) -> String in d.description }.joined(separator: "\n")
            return .failure(InterpreterError(kind: .custom("compilation"), message: msg))
        }
    }

    /// Execute a previously compiled program.
    @discardableResult
    public func execute(program: CompiledProgram) -> Result<Value, InterpreterError> {
        _debugger.load(program)
        registerBuiltins()
        registerEnumCases(from: program)
        if let limit = maxExecutionSteps { vm.executionLimit = limit }
        vm.run()

        switch vm.state {
        case .halted:
            let result = vm.stackSnapshot.last ?? .void
            return .success(result)
        case .error(let err):
            return .failure(err)
        default:
            return .success(.void)
        }
    }

    /// Execute a single expression and return its value.
    public func evaluate(
        expression: String,
        fileName: String = "<expr>"
    ) -> Result<Value, InterpreterError> {
        run(source: expression, fileName: fileName)
    }

    /// Register enum case values as globals from the compiled program's type table.
    private func registerEnumCases(from program: CompiledProgram) {
        for typeInfo in program.typeTable where typeInfo.kind == .enum {
            // Determine raw value type from conformances
            let hasIntRaw = typeInfo.conformances.contains("Int")
            let hasStringRaw = typeInfo.conformances.contains("String")

            for (i, prop) in typeInfo.properties.enumerated() {
                let qualifiedName = "\(typeInfo.name).\(prop.name)"
                var rawValue: Value? = nil
                if hasIntRaw {
                    // Auto-assign int raw values starting from 0
                    rawValue = .int(i)
                } else if hasStringRaw {
                    // String raw value = case name
                    rawValue = .string(prop.name)
                }
                // Check if typeAnnotation carries an explicit raw value
                if let annotation = prop.typeAnnotation, let intVal = Int(annotation) {
                    rawValue = .int(intVal)
                } else if let annotation = prop.typeAnnotation, annotation.hasPrefix("\"") {
                    rawValue = .string(String(annotation.dropFirst().dropLast()))
                }
                let caseRef = EnumCaseRef(typeName: typeInfo.name, caseName: prop.name, rawValue: rawValue)
                vm.environment.setGlobal(qualifiedName, value: .enumCase(caseRef))
            }
        }
    }

    /// Reset interpreter state, clearing all globals and history.
    /// Bridge registrations are preserved.
    public func reset() {
        vm.load(CompiledProgram())
    }
}
