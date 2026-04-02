import Foundation
import LanternVM

/// Registers String instance methods and properties on the given bridge registry.
public func registerStringBridge(on registry: BridgeRegistry) {
    let typeName = "String"

    // MARK: - Properties

    registry.registerProperty(typeName: typeName, name: "count", getter: { @Sendable value in
        guard let str = value.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "String", got: value.typeName)
        }
        return .int(str.count)
    }, setter: nil)

    registry.registerProperty(typeName: typeName, name: "isEmpty", getter: { @Sendable value in
        guard let str = value.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "String", got: value.typeName)
        }
        return .bool(str.isEmpty)
    }, setter: nil)

    // MARK: - Methods

    registry.registerMethod(typeName: typeName, selector: "uppercased", parameterLabels: []) { @Sendable value, _ in
        guard let str = value.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "String", got: value.typeName)
        }
        return .string(str.uppercased())
    }

    registry.registerMethod(typeName: typeName, selector: "lowercased", parameterLabels: []) { @Sendable value, _ in
        guard let str = value.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "String", got: value.typeName)
        }
        return .string(str.lowercased())
    }

    registry.registerMethod(typeName: typeName, selector: "hasPrefix", parameterLabels: [nil]) { @Sendable value, args in
        guard let str = value.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "String", got: value.typeName)
        }
        guard let prefix = args.first?.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "prefix", expected: "String", got: args.first?.typeName ?? "missing")
        }
        return .bool(str.hasPrefix(prefix))
    }

    registry.registerMethod(typeName: typeName, selector: "hasSuffix", parameterLabels: [nil]) { @Sendable value, args in
        guard let str = value.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "String", got: value.typeName)
        }
        guard let suffix = args.first?.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "suffix", expected: "String", got: args.first?.typeName ?? "missing")
        }
        return .bool(str.hasSuffix(suffix))
    }

    registry.registerMethod(typeName: typeName, selector: "contains", parameterLabels: [nil]) { @Sendable value, args in
        guard let str = value.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "String", got: value.typeName)
        }
        guard let needle = args.first?.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "other", expected: "String", got: args.first?.typeName ?? "missing")
        }
        return .bool(str.contains(needle))
    }

    registry.registerMethod(typeName: typeName, selector: "replacingOccurrences", parameterLabels: ["of", "with"]) { @Sendable value, args in
        guard let str = value.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "String", got: value.typeName)
        }
        guard args.count >= 2,
              let target = args[0].stringValue,
              let replacement = args[1].stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "of/with", expected: "String", got: "invalid arguments")
        }
        return .string(str.replacingOccurrences(of: target, with: replacement))
    }

    registry.registerMethod(typeName: typeName, selector: "split", parameterLabels: ["separator"]) { @Sendable value, args in
        guard let str = value.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "String", got: value.typeName)
        }
        guard let separator = args.first?.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "separator", expected: "String", got: args.first?.typeName ?? "missing")
        }
        let parts = str.components(separatedBy: separator).map { Value.string(String($0)) }
        return .array(parts)
    }

    registry.registerMethod(typeName: typeName, selector: "trimmingCharacters", parameterLabels: ["in"]) { @Sendable value, args in
        guard let str = value.stringValue else {
            throw BridgeError.argumentConversionFailed(parameter: "self", expected: "String", got: value.typeName)
        }
        // Default to whitespace and newlines; accept a string naming the character set.
        let characterSet: CharacterSet
        if let setName = args.first?.stringValue {
            switch setName {
            case "whitespaces": characterSet = .whitespaces
            case "whitespacesAndNewlines": characterSet = .whitespacesAndNewlines
            case "newlines": characterSet = .newlines
            case "decimalDigits": characterSet = .decimalDigits
            case "letters": characterSet = .letters
            case "punctuationCharacters": characterSet = .punctuationCharacters
            default: characterSet = .whitespacesAndNewlines
            }
        } else {
            characterSet = .whitespacesAndNewlines
        }
        return .string(str.trimmingCharacters(in: characterSet))
    }
}
