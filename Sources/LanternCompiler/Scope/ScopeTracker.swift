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

        public init(name: String, slot: UInt16, depth: Int, isMutable: Bool, typeAnnotation: String? = nil) {
            self.name = name
            self.slot = slot
            self.depth = depth
            self.isMutable = isMutable
            self.typeAnnotation = typeAnnotation
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
    public func declare(name: String, isMutable: Bool, typeAnnotation: String? = nil) -> UInt16 {
        let slot = nextSlot
        locals.append(Local(name: name, slot: slot, depth: scopeDepth, isMutable: isMutable, typeAnnotation: typeAnnotation))
        nextSlot += 1
        return slot
    }

    /// Resolve a name to its local slot. Returns nil if the name is not found.
    public func resolve(_ name: String) -> Local? {
        // Search from innermost scope outward
        for local in locals.reversed() {
            if local.name == name {
                return local
            }
        }
        return nil
    }

    /// Check if a name is declared in the current scope specifically.
    public func isDeclaredInCurrentScope(_ name: String) -> Bool {
        locals.contains { $0.name == name && $0.depth == scopeDepth }
    }

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

    /// Reserve a specific number of initial slots (e.g., for function parameters).
    public func reserveSlots(_ count: UInt16) {
        if nextSlot < count {
            nextSlot = count
        }
    }
}
