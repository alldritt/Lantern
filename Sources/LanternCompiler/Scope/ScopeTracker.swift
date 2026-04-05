import LanternVM

/// Tracks lexical scopes during compilation, mapping variable names to local slots.
public final class ScopeTracker: @unchecked Sendable {
    /// A single local variable entry.
    public struct Local {
        public let name: String
        public let slot: UInt16
        public let depth: Int
        public let isMutable: Bool
        public let typeAnnotation: String?
        /// Whether the variable has been initialized (assigned a value).
        /// A `let` without an initializer starts as false and becomes true on first assignment.
        public var isInitialized: Bool

        public init(name: String, slot: UInt16, depth: Int, isMutable: Bool, typeAnnotation: String? = nil, isInitialized: Bool = true) {
            self.name = name
            self.slot = slot
            self.depth = depth
            self.isMutable = isMutable
            self.typeAnnotation = typeAnnotation
            self.isInitialized = isInitialized
        }
    }

    private var locals: [Local] = []
    private var scopeDepth: Int = 0
    private var nextSlot: UInt16 = 0

    public init() {}

    // MARK: - Scope Management

    public var currentDepth: Int { scopeDepth }
    public var slotCount: UInt16 { nextSlot }

    public func pushScope() {
        scopeDepth += 1
    }

    public func popScope() -> [Local] {
        let removed = locals.filter { $0.depth == scopeDepth }
        locals.removeAll { $0.depth == scopeDepth }
        scopeDepth -= 1
        return removed
    }

    // MARK: - Variable Management

    @discardableResult
    public func declare(name: String, isMutable: Bool, typeAnnotation: String? = nil, isInitialized: Bool = true) -> UInt16 {
        let slot = nextSlot
        locals.append(Local(name: name, slot: slot, depth: scopeDepth, isMutable: isMutable, typeAnnotation: typeAnnotation, isInitialized: isInitialized))
        nextSlot += 1
        return slot
    }

    /// Resolve a name to its local slot. Returns nil if the name is not found.
    public func resolve(_ name: String) -> Local? {
        for local in locals.reversed() {
            if local.name == name { return local }
        }
        return nil
    }

    /// Mark a local variable as initialized (for deferred let init).
    public func markInitialized(_ name: String) {
        if let idx = locals.lastIndex(where: { $0.name == name }) {
            locals[idx].isInitialized = true
        }
    }

    /// Check if a name is declared in the current scope specifically.
    public func isDeclaredInCurrentScope(_ name: String) -> Bool {
        locals.contains { $0.name == name && $0.depth == scopeDepth }
    }

    /// All currently declared local variable names.
    public func allLocalNames() -> [String] { locals.map(\.name) }

    /// Reset the tracker for reuse.
    public func reset() {
        locals.removeAll()
        scopeDepth = 0
        nextSlot = 0
    }

    /// Save the current slot counter (for function body compilation).
    public func saveSlotState() -> UInt16 { nextSlot }

    /// Restore slot counter after function body compilation.
    public func restoreSlotState(_ saved: UInt16) { nextSlot = saved }

    /// Save full scope state (locals + slots + depth) for closure compilation.
    public func saveFullState() -> ([Local], UInt16, Int) {
        return (locals, nextSlot, scopeDepth)
    }

    /// Restore full scope state after closure compilation.
    public func restoreFullState(_ state: ([Local], UInt16, Int)) {
        locals = state.0; nextSlot = state.1; scopeDepth = state.2
    }

    /// Snapshot of which locals are initialized (for branch analysis).
    public func saveInitializedState() -> [String: Bool] {
        var state: [String: Bool] = [:]
        for local in locals { state[local.name] = local.isInitialized }
        return state
    }

    /// Restore initialized state from a snapshot.
    public func restoreInitializedState(_ state: [String: Bool]) {
        for i in locals.indices {
            if let saved = state[locals[i].name] { locals[i].isInitialized = saved }
        }
    }

    /// Merge two branch states: a local is initialized only if BOTH branches initialized it.
    public func mergeInitializedState(_ thenState: [String: Bool], _ elseState: [String: Bool]) {
        for i in locals.indices {
            let name = locals[i].name
            let thenInit = thenState[name] ?? false
            let elseInit = elseState[name] ?? false
            locals[i].isInitialized = thenInit && elseInit
        }
    }

    /// Reserve a specific number of initial slots (e.g., for function parameters).
    public func reserveSlots(_ count: UInt16) {
        if nextSlot < count {
            nextSlot = count
        }
    }
}
