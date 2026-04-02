import LanternVM

/// A snapshot of a single variable for debugger display.
public struct VariableInfo: Sendable {
    public let name: String
    public let value: Value
    public let typeName: String
    public let isMutable: Bool
    public let scopeDepth: Int

    public init(name: String, value: Value, typeName: String, isMutable: Bool, scopeDepth: Int = 0) {
        self.name = name
        self.value = value
        self.typeName = typeName
        self.isMutable = isMutable
        self.scopeDepth = scopeDepth
    }
}

/// Records the before/after state of a variable modification.
public struct VariableModification: Sendable {
    public let name: String
    public let oldValue: Value
    public let newValue: Value
    public let wasImmutable: Bool

    public init(name: String, oldValue: Value, newValue: Value, wasImmutable: Bool) {
        self.name = name
        self.oldValue = oldValue
        self.newValue = newValue
        self.wasImmutable = wasImmutable
    }
}
