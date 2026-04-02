import LanternVM

/// Registers Dictionary instance methods and properties on the given bridge registry.
public func registerDictionaryBridge(on registry: BridgeRegistry) {
    let typeName = "Dictionary"

    // MARK: - Properties

    registry.registerProperty(typeName: typeName, name: "count", getter: { @Sendable value in
        guard let dict = value.dictionaryValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "Dictionary", got: value.typeName)
        }
        return .int(dict.count)
    }, setter: nil)

    registry.registerProperty(typeName: typeName, name: "isEmpty", getter: { @Sendable value in
        guard let dict = value.dictionaryValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "Dictionary", got: value.typeName)
        }
        return .bool(dict.isEmpty)
    }, setter: nil)

    registry.registerProperty(typeName: typeName, name: "keys", getter: { @Sendable value in
        guard let dict = value.dictionaryValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "Dictionary", got: value.typeName)
        }
        let keys = dict.keys.sorted().map { Value.string($0) }
        return .array(keys)
    }, setter: nil)

    registry.registerProperty(typeName: typeName, name: "values", getter: { @Sendable value in
        guard let dict = value.dictionaryValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "Dictionary", got: value.typeName)
        }
        let values = dict.sorted(by: { $0.key < $1.key }).map(\.value)
        return .array(values)
    }, setter: nil)

    // MARK: - Methods

    registry.registerMethod(typeName: typeName, selector: "removeValue", parameterLabels: ["forKey"]) { @Sendable value, args in
        guard var dict = value.dictionaryValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "Dictionary", got: value.typeName)
        }
        guard let key = args.first?.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "forKey", expected: "String", got: args.first?.typeName ?? "missing")
        }
        dict.removeValue(forKey: key)
        return .dictionary(dict)
    }
}
