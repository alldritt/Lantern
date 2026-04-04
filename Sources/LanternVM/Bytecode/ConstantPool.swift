/// Stores compile-time constants referenced by bytecode via index.
public struct ConstantPool: Sendable {
    public var strings: [String] = []
    public var functions: [FunctionRef] = []
    public var typeNames: [String] = []
    public var propertyNames: [String] = []
    public var methodNames: [String] = []

    // Deduplication indices — O(1) lookup instead of O(n) linear scan
    private var stringIndex: [String: UInt16] = [:]
    private var typeNameIndex: [String: UInt16] = [:]
    private var propertyNameIndex: [String: UInt16] = [:]
    private var methodNameIndex: [String: UInt16] = [:]

    public init() {}

    @discardableResult
    public mutating func addString(_ s: String) -> UInt16 {
        if let i = stringIndex[s] { return i }
        let i = UInt16(strings.count); strings.append(s); stringIndex[s] = i; return i
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
        if let i = typeNameIndex[n] { return i }
        let i = UInt16(typeNames.count); typeNames.append(n); typeNameIndex[n] = i; return i
    }

    public func typeName(at index: UInt16) -> String? {
        let i = Int(index); return i < typeNames.count ? typeNames[i] : nil
    }

    @discardableResult
    public mutating func addPropertyName(_ n: String) -> UInt16 {
        if let i = propertyNameIndex[n] { return i }
        let i = UInt16(propertyNames.count); propertyNames.append(n); propertyNameIndex[n] = i; return i
    }

    public func propertyName(at index: UInt16) -> String? {
        let i = Int(index); return i < propertyNames.count ? propertyNames[i] : nil
    }

    @discardableResult
    public mutating func addMethodName(_ n: String) -> UInt16 {
        if let i = methodNameIndex[n] { return i }
        let i = UInt16(methodNames.count); methodNames.append(n); methodNameIndex[n] = i; return i
    }

    public func methodName(at index: UInt16) -> String? {
        let i = Int(index); return i < methodNames.count ? methodNames[i] : nil
    }
}
