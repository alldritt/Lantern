import LanternVM

/// The kind of symbol stored in the global symbol table.
public enum SymbolKind: Sendable {
    case function(paramCount: Int, isAsync: Bool, isThrowing: Bool)
    case type(TypeKind)
    case global(isMutable: Bool)
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

    /// Reset the table for reuse.
    public func reset() {
        symbols.removeAll()
    }
}
