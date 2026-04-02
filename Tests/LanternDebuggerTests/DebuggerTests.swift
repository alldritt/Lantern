import Testing
import Foundation
@testable import LanternVM
@testable import LanternDebugger

@Suite("Debugger")
struct DebuggerTests {
    @Test func create() { let d = Debugger(); #expect(!d.isPaused); #expect(d.isBreakOnExceptions == false) }

    @Test func addBreakpoint() {
        let d = Debugger()
        let bp = d.addBreakpoint(file: "test.swift", line: 10, condition: nil)
        #expect(bp.isEnabled)
        if case .line(let f, let l) = bp.kind { #expect(f == "test.swift"); #expect(l == 10) }
        else { Issue.record("Expected line breakpoint") }
        #expect(d.breakpoints.count == 1)
    }

    @Test func removeBreakpoint() {
        let d = Debugger()
        let bp = d.addBreakpoint(file: "t.swift", line: 5, condition: nil)
        d.removeBreakpoint(bp.id)
        #expect(d.breakpoints.isEmpty)
    }

    @Test func enableDisable() {
        let d = Debugger()
        let bp = d.addBreakpoint(file: "t.swift", line: 5, condition: nil)
        d.enableBreakpoint(bp.id, enabled: false)
        #expect(d.breakpoints.first?.isEnabled == false)
    }

    @Test func addWatchpoint() {
        let d = Debugger()
        let bp = d.addWatchpoint(variable: "count", inFrame: nil)
        if case .watchpoint(let v, _) = bp.kind { #expect(v == "count") }
        else { Issue.record("Expected watchpoint") }
    }

    @Test func addHostCallBreakpoint() {
        let d = Debugger()
        let bp = d.addHostCallBreakpoint(functionName: "fetchData", timing: .before)
        if case .hostCall(let fn, let t) = bp.kind { #expect(fn == "fetchData"); #expect(t == .before) }
        else { Issue.record("Expected host call breakpoint") }
    }

    @Test func emptyCallStack() { #expect(Debugger().callStack().isEmpty) }
    @Test func emptyGlobals() { #expect(Debugger().globals().isEmpty) }
    @Test func emptyEventLog() { #expect(Debugger().eventLog.isEmpty) }
    @Test func clearEventLog() {
        let d = Debugger(); _ = d.addBreakpoint(file: "t.swift", line: 1, condition: nil)
        d.clearEventLog(); #expect(d.eventLog.isEmpty)
    }
}
