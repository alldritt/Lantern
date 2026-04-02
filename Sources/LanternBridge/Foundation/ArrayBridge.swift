import LanternVM

/// Registers Array instance methods and properties on the given bridge registry.
public func registerArrayBridge(on registry: BridgeRegistry) {
    let typeName = "Array"

    // MARK: - Properties

    registry.registerProperty(typeName: typeName, name: "count", getter: { @Sendable value in
        guard let arr = value.arrayValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "Array", got: value.typeName)
        }
        return .int(arr.count)
    }, setter: nil)

    registry.registerProperty(typeName: typeName, name: "isEmpty", getter: { @Sendable value in
        guard let arr = value.arrayValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "Array", got: value.typeName)
        }
        return .bool(arr.isEmpty)
    }, setter: nil)

    registry.registerProperty(typeName: typeName, name: "first", getter: { @Sendable value in
        guard let arr = value.arrayValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "Array", got: value.typeName)
        }
        if let first = arr.first {
            return .optional(first)
        }
        return .optional(nil)
    }, setter: nil)

    registry.registerProperty(typeName: typeName, name: "last", getter: { @Sendable value in
        guard let arr = value.arrayValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "Array", got: value.typeName)
        }
        if let last = arr.last {
            return .optional(last)
        }
        return .optional(nil)
    }, setter: nil)

    // MARK: - Methods

    registry.registerMethod(typeName: typeName, selector: "append", parameterLabels: [nil]) { @Sendable value, args in
        guard var arr = value.arrayValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "Array", got: value.typeName)
        }
        guard let element = args.first else {
            throw BridgeError.argumentConversionFailed(parameter: "element", expected: "Value", got: "missing")
        }
        arr.append(element)
        return .array(arr)
    }

    registry.registerMethod(typeName: typeName, selector: "remove", parameterLabels: ["at"]) { @Sendable value, args in
        guard var arr = value.arrayValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "Array", got: value.typeName)
        }
        guard let index = args.first?.intValue else {
            throw BridgeError.argumentConversionFailed(parameter: "at", expected: "Int", got: args.first?.typeName ?? "missing")
        }
        guard index >= 0 && index < arr.count else {
            throw InterpreterError.indexOutOfBounds(index, count: arr.count)
        }
        arr.remove(at: index)
        return .array(arr)
    }

    registry.registerMethod(typeName: typeName, selector: "contains", parameterLabels: [nil]) { @Sendable value, args in
        guard let arr = value.arrayValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "Array", got: value.typeName)
        }
        guard let element = args.first else {
            throw BridgeError.argumentConversionFailed(parameter: "element", expected: "Value", got: "missing")
        }
        return .bool(arr.contains(element))
    }

    registry.registerMethod(typeName: typeName, selector: "reversed", parameterLabels: []) { @Sendable value, _ in
        guard let arr = value.arrayValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "Array", got: value.typeName)
        }
        return .array(arr.reversed())
    }
}
