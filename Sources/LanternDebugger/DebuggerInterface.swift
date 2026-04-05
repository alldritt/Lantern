import Foundation
import LanternVM

/// The primary protocol for controlling a Lantern debugging session.
public protocol DebuggerInterface: AnyObject {
    // MARK: - Execution Control

    func run()
    func pause()
    func stepOver()
    func stepInto()
    func stepOut()
    func stepToLine(_ line: Int, file: String)
    /// Start execution and immediately pause at the first executable statement.
    func startPaused()
    var isPaused: Bool { get }
    var pausedLocation: SourceLocation? { get }
    var pauseReason: PauseReason? { get }

    // MARK: - Breakpoints

    @discardableResult func addBreakpoint(file: String, line: Int, condition: String?) -> Breakpoint
    func removeBreakpoint(_ id: UUID)
    func enableBreakpoint(_ id: UUID, enabled: Bool)
    @discardableResult func addWatchpoint(variable: String, inFrame frameIndex: Int?) -> Breakpoint
    @discardableResult func addHostCallBreakpoint(functionName: String, timing: HostCallBreakpointTiming) -> Breakpoint
    var isBreakOnExceptions: Bool { get set }
    var breakpoints: [Breakpoint] { get }

    // MARK: - Inspection

    func callStack() -> [FrameInfo]
    func locals(frameIndex: Int) -> [VariableInfo]
    func captures(frameIndex: Int) -> [VariableInfo]
    func globals() -> [VariableInfo]
    /// The value at the top of the VM stack (last expression result) when paused.
    var lastExpressionResult: Value? { get }
    func evaluate(expression: String, inFrame frameIndex: Int) -> Result<Value, InterpreterError>

    // MARK: - Mutation

    func setVariable(name: String, value: Value, inFrame frameIndex: Int) -> Result<VariableModification, DebuggerError>
    func executeStatement(statement: String, inFrame frameIndex: Int) -> Result<Void, InterpreterError>

    // MARK: - Events

    var eventLog: [DebugEvent] { get }
    func clearEventLog()
    var delegate: DebuggerDelegate? { get set }
}
