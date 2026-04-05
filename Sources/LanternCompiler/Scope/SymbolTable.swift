import LanternVM

/// The kind of symbol stored in the global symbol table.
public enum SymbolKind: Sendable {
    case function(paramCount: Int, isAsync: Bool, isThrowing: Bool)
    case type(TypeKind)
    case global(isMutable: Bool, isInitialized: Bool = true)
    case enumCase(typeName: String)
}

/// A record in the symbol table.
public struct SymbolRecord: Sendable {
    public let name: String
    public let kind: SymbolKind
    public let location: SourceLocation

    public init(name: String, kind: SymbolKind, location: SourceLocation) {
        self.name = name
        self.kind = kind
        self.location = location
    }

    public var isType: Bool {
        if case .type = kind { return true }
        return false
    }
}

/// Global symbol table for resolving top-level functions, types, and globals.
public final class SymbolTable: @unchecked Sendable {
    private var symbols: [String: SymbolRecord] = [:]

    public init() {}

    // MARK: - Registration

    @discardableResult
    public func register(_ name: String, kind: SymbolKind, location: SourceLocation = .unknown) -> Bool {
        guard symbols[name] == nil else { return false }
        symbols[name] = SymbolRecord(name: name, kind: kind, location: location)
        return true
    }

    // MARK: - Lookup

    public func lookup(_ name: String) -> SymbolRecord? {
        symbols[name]
    }

    public func contains(_ name: String) -> Bool {
        symbols[name] != nil
    }

    // MARK: - Filtered Queries

    public var allFunctions: [SymbolRecord] {
        symbols.values.filter {
            if case .function = $0.kind { return true }
            return false
        }
    }

    public var allTypes: [SymbolRecord] {
        symbols.values.filter {
            if case .type = $0.kind { return true }
            return false
        }
    }

    public var allGlobals: [SymbolRecord] {
        symbols.values.filter {
            if case .global = $0.kind { return true }
            return false
        }
    }

    /// Mark a global variable as initialized (for deferred let).
    public func markInitialized(_ name: String) {
        guard var record = symbols[name], case .global(let isMutable, _) = record.kind else { return }
        symbols[name] = SymbolRecord(name: name, kind: .global(isMutable: isMutable, isInitialized: true), location: record.location)
    }

    /// Snapshot of global initialization states (for branch analysis).
    public func initializedSnapshot() -> [String: Bool] {
        var snap: [String: Bool] = [:]
        for (name, record) in symbols {
            if case .global(_, let isInit) = record.kind { snap[name] = isInit }
        }
        return snap
    }

    /// Restore initialization states from snapshot.
    public func restoreInitializedSnapshot(_ snap: [String: Bool]) {
        for (name, isInit) in snap {
            if var record = symbols[name], case .global(let isMutable, _) = record.kind {
                symbols[name] = SymbolRecord(name: name, kind: .global(isMutable: isMutable, isInitialized: isInit), location: record.location)
            }
        }
    }

    /// Merge two branch snapshots: initialized only if BOTH branches initialized.
    public func mergeInitializedSnapshots(_ thenSnap: [String: Bool], _ elseSnap: [String: Bool]) {
        let allKeys = Set(thenSnap.keys).union(elseSnap.keys)
        for name in allKeys {
            let thenInit = thenSnap[name] ?? false
            let elseInit = elseSnap[name] ?? false
            if var record = symbols[name], case .global(let isMutable, _) = record.kind {
                symbols[name] = SymbolRecord(name: name, kind: .global(isMutable: isMutable, isInitialized: thenInit && elseInit), location: record.location)
            }
        }
    }

    /// Reset the table for reuse.
    public func reset() {
        symbols.removeAll()
    }
}
