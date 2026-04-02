/// Stores global variables and type descriptors.
public final class Environment: @unchecked Sendable {
    private var globals: [String: Value] = [:]
    private var typeDescriptors: [String: TypeDescriptor] = [:]

    public init() {}

    public func getGlobal(_ name: String) -> Value? { globals[name] }
    public func setGlobal(_ name: String, value: Value) { globals[name] = value }
    public func allGlobals() -> [String: Value] { globals }

    public func registerType(_ descriptor: TypeDescriptor) { typeDescriptors[descriptor.name] = descriptor }
    public func getType(_ name: String) -> TypeDescriptor? { typeDescriptors[name] }
}

/// Runtime descriptor for a user-defined type.
public struct TypeDescriptor: Sendable {
    public let name: String
    public let kind: TypeKind
    public var properties: [(name: String, isMutable: Bool, defaultValue: Value?)]
    public var methods: [String: FunctionRef]
    public var computedProperties: [String: (get: FunctionRef, set: FunctionRef?)]
    public var staticProperties: [String: Value]
    public var initializers: [FunctionRef]
    public var enumCases: [(name: String, associatedValueCount: Int)]

    public init(
        name: String, kind: TypeKind,
        properties: [(name: String, isMutable: Bool, defaultValue: Value?)] = [],
        methods: [String: FunctionRef] = [:],
        computedProperties: [String: (get: FunctionRef, set: FunctionRef?)] = [:],
        staticProperties: [String: Value] = [:],
        initializers: [FunctionRef] = [],
        enumCases: [(name: String, associatedValueCount: Int)] = []
    ) {
        self.name = name; self.kind = kind; self.properties = properties
        self.methods = methods; self.computedProperties = computedProperties
        self.staticProperties = staticProperties; self.initializers = initializers
        self.enumCases = enumCases
    }
}
