import LanternVM

/// A named native function that can be invoked from the interpreter.
public struct NativeFunction: Sendable {
    public let name: String
    public let arity: Int
    public let implementation: @Sendable ([Value]) throws -> Value

    public init(name: String, arity: Int, implementation: @escaping @Sendable ([Value]) throws -> Value) {
        self.name = name
        self.arity = arity
        self.implementation = implementation
    }
}
