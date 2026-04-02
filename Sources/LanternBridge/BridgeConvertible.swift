import Foundation
import LanternVM

/// Protocol for types that can convert to and from interpreter `Value` instances.
public protocol BridgeConvertible {
    static func fromInterpreterValue(_ value: Value) -> Self?
    func toInterpreterValue() -> Value
}

// MARK: - Standard Conformances

extension Int: BridgeConvertible {
    public static func fromInterpreterValue(_ value: Value) -> Int? {
        value.intValue
    }
    public func toInterpreterValue() -> Value {
        .int(self)
    }
}

extension Double: BridgeConvertible {
    public static func fromInterpreterValue(_ value: Value) -> Double? {
        value.doubleValue
    }
    public func toInterpreterValue() -> Value {
        .double(self)
    }
}

extension Bool: BridgeConvertible {
    public static func fromInterpreterValue(_ value: Value) -> Bool? {
        value.boolValue
    }
    public func toInterpreterValue() -> Value {
        .bool(self)
    }
}

extension String: BridgeConvertible {
    public static func fromInterpreterValue(_ value: Value) -> String? {
        value.stringValue
    }
    public func toInterpreterValue() -> Value {
        .string(self)
    }
}

extension Date: BridgeConvertible {
    public static func fromInterpreterValue(_ value: Value) -> Date? {
        guard let interval = value.doubleValue else { return nil }
        return Date(timeIntervalSince1970: interval)
    }
    public func toInterpreterValue() -> Value {
        .double(timeIntervalSince1970)
    }
}

extension URL: BridgeConvertible {
    public static func fromInterpreterValue(_ value: Value) -> URL? {
        guard let str = value.stringValue else { return nil }
        return URL(string: str)
    }
    public func toInterpreterValue() -> Value {
        .string(absoluteString)
    }
}

extension UUID: BridgeConvertible {
    public static func fromInterpreterValue(_ value: Value) -> UUID? {
        guard let str = value.stringValue else { return nil }
        return UUID(uuidString: str)
    }
    public func toInterpreterValue() -> Value {
        .string(uuidString)
    }
}

extension Data: BridgeConvertible {
    public static func fromInterpreterValue(_ value: Value) -> Data? {
        if let arr = value.arrayValue {
            let bytes = arr.compactMap { $0.intValue.flatMap { UInt8(exactly: $0) } }
            guard bytes.count == arr.count else { return nil }
            return Data(bytes)
        }
        if let str = value.stringValue {
            return Data(str.utf8)
        }
        return nil
    }
    public func toInterpreterValue() -> Value {
        .array(map { Value.int(Int($0)) })
    }
}

extension Array: BridgeConvertible where Element == Value {
    public static func fromInterpreterValue(_ value: Value) -> [Value]? {
        value.arrayValue
    }
    public func toInterpreterValue() -> Value {
        .array(self)
    }
}

extension Dictionary: BridgeConvertible where Key == String, Value == LanternVM.Value {
    public static func fromInterpreterValue(_ value: LanternVM.Value) -> [String: LanternVM.Value]? {
        value.dictionaryValue
    }
    public func toInterpreterValue() -> LanternVM.Value {
        .dictionary(self)
    }
}
