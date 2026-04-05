import Foundation
import LanternVM

/// The central registry that maps Lantern type names, methods, properties,
/// and free functions to their native Swift implementations.
public final class BridgeRegistry: @unchecked Sendable {

    // MARK: - Storage Types

    private struct TypeRegistration {
        var constructor: (([Value]) throws -> Value)?
        var initializers: [String: ([Value]) throws -> Value] // keyed by label signature
        var methods: [String: (Value, [Value]) throws -> Value]
        var staticMethods: [String: ([Value]) throws -> Value]
        var properties: [String: (getter: (Value) throws -> Value, setter: ((Value, Value) throws -> Void)?)]
        var staticProperties: [String: (getter: () throws -> Value, setter: ((Value) throws -> Void)?)]
        var asyncMethods: [String: (Value, [Value]) async throws -> Value]
        var debugSummary: ((Value) -> String)?
        var debugChildren: ((Value) -> [DebugChild]?)?
    }

    private struct FunctionRegistration {
        let implementation: ([Value]) throws -> Value
    }

    private struct AsyncFunctionRegistration {
        let implementation: ([Value]) async throws -> Value
    }

    // MARK: - Storage

    private let lock = NSLock()
    private var types: [String: TypeRegistration] = [:]
    private var functions: [String: FunctionRegistration] = [:]
    private var asyncFunctions: [String: AsyncFunctionRegistration] = [:]

    /// Optional observer for host-side calls.
    public var hostCallObserver: HostCallObserver?

    // MARK: - Init

    public init() {}

    /// A pre-populated registry containing the standard Foundation bridges.
    public static var `default`: BridgeRegistry {
        let registry = BridgeRegistry()
        registerStringBridge(on: registry)
        registerArrayBridge(on: registry)
        registerDictionaryBridge(on: registry)
        registerDateBridge(on: registry)
        registerURLBridge(on: registry)
        registerUUIDBridge(on: registry)
        registerUserDefaultsBridge(on: registry)
        registerJSONBridge(on: registry)
        registerTimerBridge(on: registry)
        return registry
    }

    // MARK: - Private Helpers

    private func ensureType(_ name: String) {
        if types[name] == nil {
            types[name] = TypeRegistration(
                constructor: nil,
                initializers: [:],
                methods: [:],
                staticMethods: [:],
                properties: [:],
                staticProperties: [:],
                asyncMethods: [:],
                debugSummary: nil,
                debugChildren: nil
            )
        }
    }

    private static func labelSignature(_ labels: [String?]) -> String {
        labels.map { $0 ?? "_" }.joined(separator: ":")
    }

    // MARK: - Type Registration

    public func registerType(_ name: String, constructor: @escaping ([Value]) throws -> Value) {
        lock.lock()
        defer { lock.unlock() }
        ensureType(name)
        types[name]!.constructor = constructor
    }

    public func registerInitializer(typeName: String, parameterLabels: [String?], initializer: @escaping ([Value]) throws -> Value) {
        lock.lock()
        defer { lock.unlock() }
        ensureType(typeName)
        let key = Self.labelSignature(parameterLabels)
        types[typeName]!.initializers[key] = initializer
    }

    // MARK: - Method Registration

    public func registerMethod(typeName: String, selector: String, parameterLabels: [String?], method: @escaping (Value, [Value]) throws -> Value) {
        lock.lock()
        defer { lock.unlock() }
        ensureType(typeName)
        types[typeName]!.methods[selector] = method
    }

    public func registerStaticMethod(typeName: String, selector: String, parameterLabels: [String?], method: @escaping ([Value]) throws -> Value) {
        lock.lock()
        defer { lock.unlock() }
        ensureType(typeName)
        types[typeName]!.staticMethods[selector] = method
    }

    // MARK: - Property Registration

    public func registerProperty(typeName: String, name: String, getter: @escaping (Value) throws -> Value, setter: ((Value, Value) throws -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        ensureType(typeName)
        types[typeName]!.properties[name] = (getter: getter, setter: setter)
    }

    public func registerStaticProperty(typeName: String, name: String, getter: @escaping () throws -> Value, setter: ((Value) throws -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        ensureType(typeName)
        types[typeName]!.staticProperties[name] = (getter: getter, setter: setter)
    }

    // MARK: - Free Function Registration

    public func registerFunction(_ name: String, parameterLabels: [String?], function: @escaping ([Value]) throws -> Value) {
        lock.lock()
        defer { lock.unlock() }
        functions[name] = FunctionRegistration(implementation: function)
    }

    // MARK: - Async Registration

    public func registerAsyncMethod(typeName: String, selector: String, parameterLabels: [String?], method: @escaping (Value, [Value]) async throws -> Value) {
        lock.lock()
        defer { lock.unlock() }
        ensureType(typeName)
        types[typeName]!.asyncMethods[selector] = method
    }

    public func registerAsyncFunction(_ name: String, parameterLabels: [String?], function: @escaping ([Value]) async throws -> Value) {
        lock.lock()
        defer { lock.unlock() }
        asyncFunctions[name] = AsyncFunctionRegistration(implementation: function)
    }

    // MARK: - Debug Display

    public func registerDebugDisplay(typeName: String, summary: @escaping (Value) -> String, children: @escaping (Value) -> [DebugChild]?) {
        lock.lock()
        defer { lock.unlock() }
        ensureType(typeName)
        types[typeName]!.debugSummary = summary
        types[typeName]!.debugChildren = children
    }

    // MARK: - Queries

    public func isTypeRegistered(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return types[name] != nil
    }

    public func isMethodRegistered(typeName: String, selector: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let reg = types[typeName] else { return false }
        return reg.methods[selector] != nil || reg.asyncMethods[selector] != nil
    }

    public var registeredTypes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(types.keys).sorted()
    }

    public func registeredMethods(forType name: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard let reg = types[name] else { return [] }
        let sync = Array(reg.methods.keys)
        let async_ = Array(reg.asyncMethods.keys)
        return (sync + async_).sorted()
    }

    public func registeredProperties(forType name: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard let reg = types[name] else { return [] }
        return Array(reg.properties.keys).sorted()
    }

    public var registeredFunctions: [String] {
        lock.lock()
        defer { lock.unlock() }
        let sync = Array(functions.keys)
        let async_ = Array(asyncFunctions.keys)
        return (sync + async_).sorted()
    }

    // MARK: - Lookup (for VM dispatch)

    public func lookupConstructor(_ typeName: String) -> (([Value]) throws -> Value)? {
        lock.lock()
        defer { lock.unlock() }
        return types[typeName]?.constructor
    }

    public func lookupMethod(typeName: String, selector: String) -> ((Value, [Value]) throws -> Value)? {
        lock.lock()
        defer { lock.unlock() }
        return types[typeName]?.methods[selector]
    }

    public func lookupProperty(typeName: String, name: String) -> (getter: (Value) throws -> Value, setter: ((Value, Value) throws -> Void)?)? {
        lock.lock()
        defer { lock.unlock() }
        return types[typeName]?.properties[name]
    }

    public func lookupFunction(_ name: String) -> (([Value]) throws -> Value)? {
        lock.lock()
        defer { lock.unlock() }
        return functions[name]?.implementation
    }
}
