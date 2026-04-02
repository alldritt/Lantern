/// Stores compile-time constants referenced by bytecode via index.
public struct ConstantPool: Sendable {
    public var strings: [String] = []
    public var functions: [FunctionRef] = []
    public var typeNames: [String] = []
    public var propertyNames: [String] = []
    public var methodNames: [String] = []

    public init() {}

    @discardableResult
    public mutating func addString(_ s: String) -> UInt16 {
        if let i = strings.firstIndex(of: s) { return UInt16(i) }
        let i = strings.count; strings.append(s); return UInt16(i)
    }

    public func string(at index: UInt16) -> String? {
        let i = Int(index); return i < strings.count ? strings[i] : nil
    }

    @discardableResult
    public mutating func addFunction(_ f: FunctionRef) -> UInt16 {
        let i = functions.count; functions.append(f); return UInt16(i)
    }

    public func function(at index: UInt16) -> FunctionRef? {
        let i = Int(index); return i < functions.count ? functions[i] : nil
    }

    @discardableResult
    public mutating func addTypeName(_ n: String) -> UInt16 {
        if let i = typeNames.firstIndex(of: n) { return UInt16(i) }
        let i = typeNames.count; typeNames.append(n); return UInt16(i)
    }

    public func typeName(at index: UInt16) -> String? {
        let i = Int(index); return i < typeNames.count ? typeNames[i] : nil
    }

    @discardableResult
    public mutating func addPropertyName(_ n: String) -> UInt16 {
        if let i = propertyNames.firstIndex(of: n) { return UInt16(i) }
        let i = propertyNames.count; propertyNames.append(n); return UInt16(i)
    }

    public func propertyName(at index: UInt16) -> String? {
        let i = Int(index); return i < propertyNames.count ? propertyNames[i] : nil
    }

    @discardableResult
    public mutating func addMethodName(_ n: String) -> UInt16 {
        if let i = methodNames.firstIndex(of: n) { return UInt16(i) }
        let i = methodNames.count; methodNames.append(n); return UInt16(i)
    }

    public func methodName(at index: UInt16) -> String? {
        let i = Int(index); return i < methodNames.count ? methodNames[i] : nil
    }
}
