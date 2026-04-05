import Foundation
import LanternVM

/// Bridge registration for JSONEncoder and JSONDecoder.
public func registerJSONBridge(on registry: BridgeRegistry) {
    // JSONEncoder — encode Value to JSON string
    registry.registerType("JSONEncoder") { _ in
        .hostObject(HostObjectRef(object: JSONEncoder(), typeName: "JSONEncoder"))
    }

    registry.registerMethod(typeName: "JSONEncoder", selector: "encode", parameterLabels: ["_"]) { receiver, args in
        guard let value = args.first else { return .nil_ }
        // Convert Value to a JSON-compatible object, then serialize
        let jsonObj = valueToJSONObject(value)
        guard JSONSerialization.isValidJSONObject([jsonObj]) else { return .nil_ }
        guard let data = try? JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return .nil_ }
        return .string(str)
    }

    // JSONDecoder — decode JSON string to Value
    registry.registerType("JSONDecoder") { _ in
        .hostObject(HostObjectRef(object: JSONDecoder(), typeName: "JSONDecoder"))
    }

    registry.registerMethod(typeName: "JSONDecoder", selector: "decode", parameterLabels: ["_"]) { _, args in
        guard let jsonString = args.first?.stringValue,
              let data = jsonString.data(using: .utf8),
              let jsonObj = try? JSONSerialization.jsonObject(with: data) else { return .nil_ }
        return jsonObjectToValue(jsonObj)
    }
}

// MARK: - JSON ↔ Value Conversion

private func valueToJSONObject(_ value: Value) -> Any {
    switch value {
    case .int(let v): return v
    case .double(let v): return v
    case .bool(let v): return v
    case .string(let v): return v
    case .nil_: return NSNull()
    case .array(let a): return a.map { valueToJSONObject($0) }
    case .dictionary(let d): return d.mapValues { valueToJSONObject($0) }
    case .optional(.some(let v)): return valueToJSONObject(v)
    case .optional(.none): return NSNull()
    default: return "\(value)"
    }
}

private func jsonObjectToValue(_ obj: Any) -> Value {
    switch obj {
    case let n as NSNumber:
        if CFBooleanGetTypeID() == CFGetTypeID(n) { return .bool(n.boolValue) }
        if n.doubleValue == Double(n.intValue) { return .int(n.intValue) }
        return .double(n.doubleValue)
    case let s as String: return .string(s)
    case let a as [Any]: return .array(a.map { jsonObjectToValue($0) })
    case let d as [String: Any]: return .dictionary(d.mapValues { jsonObjectToValue($0) })
    case is NSNull: return .nil_
    default: return .string("\(obj)")
    }
}
