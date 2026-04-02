/// A native (host) function callable from interpreted code.
public struct NativeFunctionRef: @unchecked Sendable {
    public let name: String
    public let arity: Int // -1 for variadic
    public let body: ([Value]) throws -> Value

    public init(name: String, arity: Int = -1, body: @escaping ([Value]) throws -> Value) {
        self.name = name; self.arity = arity; self.body = body
    }
}

/// A compiled function reference.
public struct FunctionRef: Sendable {
    /// The function name. Anonymous closures use a generated name.
    public let name: String

    /// Parameter names and labels.
    public let parameters: [ParameterInfo]

    /// Number of local variable slots required.
    public let localCount: UInt16

    /// Whether this function is async.
    public let isAsync: Bool

    /// Whether this function can throw.
    public let isThrowing: Bool

    /// The bytecode for this function's body.
    public let bytecode: [UInt8]

    /// Exception handler table for do/try/catch.
    public let exceptionHandlers: [ExceptionHandler]

    public init(
        name: String,
        parameters: [ParameterInfo] = [],
        localCount: UInt16 = 0,
        isAsync: Bool = false,
        isThrowing: Bool = false,
        bytecode: [UInt8] = [],
        exceptionHandlers: [ExceptionHandler] = []
    ) {
        self.name = name
        self.parameters = parameters
        self.localCount = localCount
        self.isAsync = isAsync
        self.isThrowing = isThrowing
        self.bytecode = bytecode
        self.exceptionHandlers = exceptionHandlers
    }

    /// Number of required parameters.
    public var arity: Int { parameters.filter { !$0.hasDefault }.count }

    /// Total parameter count including those with defaults.
    public var totalParameterCount: Int { parameters.count }
}

/// Parameter metadata.
public struct ParameterInfo: Sendable, Equatable {
    public let label: String?
    public let name: String
    public let typeAnnotation: String?
    public let hasDefault: Bool

    public init(label: String? = nil, name: String, typeAnnotation: String? = nil, hasDefault: Bool = false) {
        self.label = label
        self.name = name
        self.typeAnnotation = typeAnnotation
        self.hasDefault = hasDefault
    }
}

/// Exception handler table entry for do/try/catch.
public struct ExceptionHandler: Sendable {
    public let tryStart: Int
    public let tryEnd: Int
    public let handlerStart: Int
    public let handlerSlot: UInt16

    public init(tryStart: Int, tryEnd: Int, handlerStart: Int, handlerSlot: UInt16) {
        self.tryStart = tryStart
        self.tryEnd = tryEnd
        self.handlerStart = handlerStart
        self.handlerSlot = handlerSlot
    }
}

/// A compiled closure: function + captured values.
public struct ClosureRef: Sendable {
    public let function: FunctionRef
    public let captures: [Value]

    public init(function: FunctionRef, captures: [Value] = []) {
        self.function = function
        self.captures = captures
    }
}

/// A reference to a host (native Swift) object.
public final class HostObjectRef: @unchecked Sendable {
    public let object: AnyObject
    public let typeName: String

    public init(object: AnyObject, typeName: String) {
        self.object = object
        self.typeName = typeName
    }
}

/// A reference to an interpreted struct/class instance.
public final class InstanceRef: @unchecked Sendable {
    public let typeName: String
    public let kind: TypeKind
    private var storage: [(name: String, value: Value)]

    public init(typeName: String, kind: TypeKind = .struct, properties: [(name: String, value: Value)] = []) {
        self.typeName = typeName
        self.kind = kind
        self.storage = properties
    }

    public func property(_ name: String) -> Value? {
        storage.first(where: { $0.name == name })?.value
    }

    public func setProperty(_ name: String, _ value: Value) {
        if let idx = storage.firstIndex(where: { $0.name == name }) {
            storage[idx].value = value
        } else {
            storage.append((name: name, value: value))
        }
    }

    public var propertyNames: [String] { storage.map(\.name) }
}

/// A reference to an enum case value.
public struct EnumCaseRef: Sendable, Equatable {
    public let typeName: String
    public let caseName: String
    public let associatedValues: [Value]?
    public let rawValue: Value?  // Note: indirect via Value enum

    public init(typeName: String, caseName: String, associatedValues: [Value]? = nil, rawValue: Value? = nil) {
        self.typeName = typeName
        self.caseName = caseName
        self.associatedValues = associatedValues
        self.rawValue = rawValue
    }

    public static func == (lhs: EnumCaseRef, rhs: EnumCaseRef) -> Bool {
        lhs.typeName == rhs.typeName && lhs.caseName == rhs.caseName
            && lhs.associatedValues == rhs.associatedValues
    }
}

/// Kind of user-defined type.
public enum TypeKind: String, Sendable {
    case `struct`, `class`, `enum`
}
