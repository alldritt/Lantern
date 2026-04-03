/// The universal runtime value type for the Lantern interpreter.
public indirect enum Value: Sendable, CustomStringConvertible {
    case int(Int)
    case double(Double)
    case bool(Bool)
    case string(String)
    case nil_
    case array([Value])
    case dictionary([String: Value])
    case optional(Value?)
    case closure(ClosureRef)
    case nativeFunction(NativeFunctionRef)
    case hostObject(HostObjectRef)
    case instance(InstanceRef)
    case enumCase(EnumCaseRef)
    case range(Int, Int, Bool) // start, end, inclusive
    case void

    // MARK: - Type Queries

    /// A human-readable type name.
    public var typeName: String {
        switch self {
        case .int: return "Int"
        case .double: return "Double"
        case .bool: return "Bool"
        case .string: return "String"
        case .nil_: return "Nil"
        case .array: return "Array"
        case .dictionary: return "Dictionary"
        case .optional: return "Optional"
        case .closure: return "Closure"
        case .nativeFunction(let ref): return "NativeFunction(\(ref.name))"
        case .hostObject(let ref): return ref.typeName
        case .instance(let ref): return ref.typeName
        case .enumCase(let ref): return ref.typeName
        case .range: return "Range"
        case .void: return "Void"
        }
    }

    /// True if this value is nil or .optional(nil).
    public var isNil: Bool {
        switch self {
        case .nil_: return true
        case .optional(.none): return true
        default: return false
        }
    }

    // MARK: - Convenience Accessors

    public var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }
    public var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }
    public var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
    public var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
    public var arrayValue: [Value]? {
        if case .array(let v) = self { return v }
        return nil
    }
    public var dictionaryValue: [String: Value]? {
        if case .dictionary(let v) = self { return v }
        return nil
    }
    public var hostObjectRef: HostObjectRef? {
        if case .hostObject(let v) = self { return v }
        return nil
    }

    /// Whether this value is truthy (used in conditions).
    public var isTruthy: Bool {
        switch self {
        case .bool(let v): return v
        case .nil_: return false
        case .optional(.none): return false
        case .optional(.some): return true
        case .int(let v): return v != 0
        case .void: return false
        default: return true
        }
    }

    // MARK: - CustomStringConvertible (matches Swift interpolation)

    public var description: String {
        switch self {
        case .int(let v): return "\(v)"
        case .double(let v): return "\(v)"
        case .bool(let v): return "\(v)"
        case .string(let v): return v
        case .nil_: return "nil"
        case .optional(.none): return "nil"
        case .optional(.some(let v)): return "Optional(\(v))"
        case .array(let a):
            let elems = a.map { elem -> String in
                if case .string(let s) = elem { return "\"\(s)\"" }
                return elem.description
            }
            return "[\(elems.joined(separator: ", "))]"
        case .dictionary(let d):
            let pairs = d.sorted(by: { $0.key < $1.key }).map { pair -> String in
                let valStr: String
                if case .string(let s) = pair.value { valStr = "\"\(s)\"" }
                else { valStr = pair.value.description }
                return "\"\(pair.key)\": \(valStr)"
            }
            return "[\(pairs.joined(separator: ", "))]"
        case .range(let s, let e, let inc): return inc ? "\(s)...\(e)" : "\(s)..<\(e)"
        case .closure(let c): return "(Function \(c.function.name))"
        case .nativeFunction(let f): return "(NativeFunction \(f.name))"
        case .hostObject(let h): return "<\(h.typeName)>"
        case .instance(let i): return "\(i.typeName)(...)"
        case .enumCase(let e):
            if let av = e.associatedValues, !av.isEmpty {
                return "\(e.typeName).\(e.caseName)(\(av.map(\.description).joined(separator: ", ")))"
            }
            return "\(e.typeName).\(e.caseName)"
        case .void: return "()"
        }
    }

    // MARK: - Debug Display

    /// One-line summary for debugger display.
    public var debugSummary: String {
        switch self {
        case .string(let v):
            if v.count > 64 { return "\"\(v.prefix(64))\"... (\(v.count) characters)" }
            return "\"\(v)\""
        case .array(let a): return "Array (\(a.count) elements)"
        case .dictionary(let d): return "Dictionary (\(d.count) entries)"
        case .optional(let v):
            if let v { return "Optional(\(v.debugSummary))" }
            return "nil"
        case .instance(let i): return "\(i.typeName)(...)"
        default: return description
        }
    }

    /// Child elements for expandable debugger display.
    public var debugChildren: [DebugChild]? {
        switch self {
        case .array(let a):
            return a.enumerated().map { DebugChild(label: "[\($0.offset)]", value: $0.element) }
        case .dictionary(let d):
            return d.sorted(by: { $0.key < $1.key }).map { DebugChild(label: $0.key, value: $0.value) }
        case .instance(let i):
            return i.propertyNames.compactMap { name in
                guard let val = i.property(name) else { return nil }
                return DebugChild(label: name, value: val)
            }
        case .optional(.some(let v)):
            return [DebugChild(label: "some", value: v)]
        case .enumCase(let e):
            guard let av = e.associatedValues, !av.isEmpty else { return nil }
            return av.enumerated().map { DebugChild(label: ".\($0.offset)", value: $0.element) }
        default:
            return nil
        }
    }
}

// MARK: - Equatable

extension Value: Equatable {
    public static func == (lhs: Value, rhs: Value) -> Bool {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.nil_, .nil_): return true
        case (.void, .void): return true
        case (.array(let a), .array(let b)): return a == b
        case (.dictionary(let a), .dictionary(let b)): return a == b
        case (.range(let s1, let e1, let i1), .range(let s2, let e2, let i2)):
            return s1 == s2 && e1 == e2 && i1 == i2
        case (.enumCase(let a), .enumCase(let b)): return a == b
        case (.optional(let a), .optional(let b)):
            switch (a, b) {
            case (.none, .none): return true
            case (.some(let va), .some(let vb)): return va == vb
            default: return false
            }
        // nil comparisons with optional
        case (.nil_, .optional(.none)): return true
        case (.optional(.none), .nil_): return true
        case (.instance(let a), .instance(let b)):
            if a.kind == .class { return a === b } // Classes: identity
            // Structs: structural equality
            guard a.typeName == b.typeName, a.propertyNames == b.propertyNames else { return false }
            return a.propertyNames.allSatisfy { a.property($0) == b.property($0) }
        default: return false
        }
    }
}

// MARK: - Debug Child

public struct DebugChild: Sendable {
    public let label: String
    public let value: Value
    public init(label: String, value: Value) {
        self.label = label
        self.value = value
    }
}
