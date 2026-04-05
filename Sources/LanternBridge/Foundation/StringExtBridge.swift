import Foundation
import LanternVM

/// Bridge registration for additional String methods beyond the basics.
public func registerStringExtBridge(on registry: BridgeRegistry) {
    // components(separatedBy:)
    registry.registerMethod(typeName: "String", selector: "components", parameterLabels: ["separatedBy"]) { receiver, args in
        guard case .string(let s) = receiver, let sep = args.first?.stringValue else { return .array([]) }
        return .array(s.components(separatedBy: sep).map { .string($0) })
    }

    // data(using:) — returns Data
    registry.registerMethod(typeName: "String", selector: "data", parameterLabels: ["using"]) { receiver, _ in
        guard case .string(let s) = receiver else { return .nil_ }
        if let data = s.data(using: .utf8) {
            return .hostObject(HostObjectRef(object: data as NSData, typeName: "Data"))
        }
        return .nil_
    }

    // padding(toLength:withPad:startingAt:)
    registry.registerMethod(typeName: "String", selector: "padding", parameterLabels: ["toLength", "withPad", "startingAt"]) { receiver, args in
        guard case .string(let s) = receiver, let length = args.first?.intValue else { return receiver }
        let pad = args.count > 1 ? args[1].stringValue ?? " " : " "
        let start = args.count > 2 ? args[2].intValue ?? 0 : 0
        return .string(s.padding(toLength: length, withPad: pad, startingAt: start))
    }

    // starts(with:)
    registry.registerMethod(typeName: "String", selector: "starts", parameterLabels: ["with"]) { receiver, args in
        guard case .string(let s) = receiver, let prefix = args.first?.stringValue else { return .bool(false) }
        return .bool(s.starts(with: prefix))
    }

    // range(of:) — returns bool for simplicity (contains-like check with options)
    registry.registerMethod(typeName: "String", selector: "range", parameterLabels: ["of"]) { receiver, args in
        guard case .string(let s) = receiver, let target = args.first?.stringValue else { return .nil_ }
        return .bool(s.range(of: target) != nil)
    }

    // matches(regex:) — simplified regex check
    registry.registerMethod(typeName: "String", selector: "matches", parameterLabels: ["_"]) { receiver, args in
        guard case .string(let s) = receiver, let pattern = args.first?.stringValue else { return .bool(false) }
        return .bool(s.range(of: pattern, options: .regularExpression) != nil)
    }

    // addingPercentEncoding(withAllowedCharacters:)
    registry.registerMethod(typeName: "String", selector: "addingPercentEncoding", parameterLabels: []) { receiver, _ in
        guard case .string(let s) = receiver else { return receiver }
        return .string(s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s)
    }

    // removingPercentEncoding
    registry.registerProperty(typeName: "String", name: "removingPercentEncoding", getter: { receiver in
        guard case .string(let s) = receiver else { return receiver }
        return .string(s.removingPercentEncoding ?? s)
    }, setter: nil)

    // localizedCapitalized / localizedUppercase / localizedLowercase
    registry.registerProperty(typeName: "String", name: "capitalized", getter: { receiver in
        guard case .string(let s) = receiver else { return receiver }
        return .string(s.capitalized)
    }, setter: nil)

    // first / last character
    registry.registerProperty(typeName: "String", name: "first", getter: { receiver in
        guard case .string(let s) = receiver, let ch = s.first else { return .nil_ }
        return .optional(.string(String(ch)))
    }, setter: nil)

    registry.registerProperty(typeName: "String", name: "last", getter: { receiver in
        guard case .string(let s) = receiver, let ch = s.last else { return .nil_ }
        return .optional(.string(String(ch)))
    }, setter: nil)
}
