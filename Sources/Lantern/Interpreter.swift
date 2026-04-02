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
        vm.load(program)
        registerBuiltins() // re-register after load clears environment
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

    /// Reset interpreter state, clearing all globals and history.
    /// Bridge registrations are preserved.
    public func reset() {
        vm.load(CompiledProgram())
    }
}
