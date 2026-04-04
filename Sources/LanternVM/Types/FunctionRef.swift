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

    /// Bytecode offset of this function's body in the shared program bytecode.
    /// Set by the compiler. -1 means not yet resolved.
    public var bytecodeOffset: Int

    public init(
        name: String,
        parameters: [ParameterInfo] = [],
        localCount: UInt16 = 0,
        isAsync: Bool = false,
        isThrowing: Bool = false,
        bytecode: [UInt8] = [],
        exceptionHandlers: [ExceptionHandler] = [],
        bytecodeOffset: Int = -1
    ) {
        self.name = name
        self.parameters = parameters
        self.localCount = localCount
        self.isAsync = isAsync
        self.isThrowing = isThrowing
        self.bytecode = bytecode
        self.exceptionHandlers = exceptionHandlers
        self.bytecodeOffset = bytecodeOffset
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

/// A heap-allocated cell for mutable closure captures.
/// Both the enclosing scope and the closure share the same cell.
public final class CaptureCell: @unchecked Sendable {
    public var value: Value
    public init(_ value: Value) { self.value = value }
}

/// A compiled closure: function + captured values.
public struct ClosureRef: Sendable {
    public let function: FunctionRef
    public let captures: [CaptureCell]

    public init(function: FunctionRef, captures: [CaptureCell] = []) {
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
    private var values: [Value]
    private var nameIndex: [String: Int]

    public init(typeName: String, kind: TypeKind = .struct, properties: [(name: String, value: Value)] = []) {
        self.typeName = typeName
        self.kind = kind
        self.values = properties.map(\.value)
        self.nameIndex = Dictionary(uniqueKeysWithValues: properties.enumerated().map { ($1.name, $0) })
    }

    public func property(_ name: String) -> Value? {
        guard let idx = nameIndex[name] else { return nil }
        return values[idx]
    }

    public func setProperty(_ name: String, _ value: Value) {
        if let idx = nameIndex[name] {
            values[idx] = value
        } else {
            nameIndex[name] = values.count
            values.append(value)
        }
    }

    public var propertyNames: [String] {
        nameIndex.sorted(by: { $0.value < $1.value }).map(\.key)
    }

    /// Create a shallow copy (for struct value semantics).
    public func copy() -> InstanceRef {
        let props = nameIndex.sorted(by: { $0.value < $1.value }).map { (name: $0.key, value: values[$0.value]) }
        return InstanceRef(typeName: typeName, kind: kind, properties: props)
    }
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
