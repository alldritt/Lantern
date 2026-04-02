import Foundation
import LanternVM

/// A user-set breakpoint, watchpoint, or other pause trigger.
public struct Breakpoint: Identifiable, Sendable {
    public let id: UUID
    public let kind: BreakpointKind
    public var isEnabled: Bool
    public var condition: String?
    public var hitCount: Int
    public var ignoreCount: Int
    public var resolvedLocation: SourceLocation?

    // Internal: bytecode offsets where the breakpoint opcode was patched in.
    var resolvedOffsets: Set<Int>
    // Internal: original opcodes that were replaced, keyed by bytecode offset.
    var originalOpcodes: [Int: UInt8]

    public init(
        id: UUID = UUID(),
        kind: BreakpointKind,
        isEnabled: Bool = true,
        condition: String? = nil,
        hitCount: Int = 0,
        ignoreCount: Int = 0,
        resolvedLocation: SourceLocation? = nil,
        resolvedOffsets: Set<Int> = [],
        originalOpcodes: [Int: UInt8] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
        self.condition = condition
        self.hitCount = hitCount
        self.ignoreCount = ignoreCount
        self.resolvedLocation = resolvedLocation
        self.resolvedOffsets = resolvedOffsets
        self.originalOpcodes = originalOpcodes
    }
}

/// The kind of breakpoint.
public enum BreakpointKind: Sendable {
    case line(file: String, line: Int)
    case watchpoint(variable: String, frameIndex: Int?)
    case exception
    case hostCall(functionName: String, timing: HostCallBreakpointTiming)
}

/// Whether a host-call breakpoint fires before or after the call.
public enum HostCallBreakpointTiming: Sendable {
    case before, after
}
