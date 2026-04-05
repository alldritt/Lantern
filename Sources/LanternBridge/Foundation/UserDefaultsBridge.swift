import Foundation
import LanternVM

/// Bridge registration for UserDefaults.
public func registerUserDefaultsBridge(on registry: BridgeRegistry) {
    // UserDefaults.standard
    registry.registerStaticProperty(typeName: "UserDefaults", name: "standard", getter: {
        .hostObject(HostObjectRef(object: UserDefaults.standard, typeName: "UserDefaults"))
    }, setter: nil)

    // set(_:forKey:)
    registry.registerMethod(typeName: "UserDefaults", selector: "set", parameterLabels: ["_", "forKey"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let defaults = ref.object as? UserDefaults,
              args.count >= 2, let key = args[1].stringValue else { return .void }
        let value = args[0]
        switch value {
        case .int(let v): defaults.set(v, forKey: key)
        case .double(let v): defaults.set(v, forKey: key)
        case .bool(let v): defaults.set(v, forKey: key)
        case .string(let v): defaults.set(v, forKey: key)
        default: break
        }
        return .void
    }

    // string(forKey:)
    registry.registerMethod(typeName: "UserDefaults", selector: "string", parameterLabels: ["forKey"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let defaults = ref.object as? UserDefaults,
              let key = args.first?.stringValue else { return .nil_ }
        return defaults.string(forKey: key).map { .string($0) } ?? .nil_
    }

    // integer(forKey:)
    registry.registerMethod(typeName: "UserDefaults", selector: "integer", parameterLabels: ["forKey"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let defaults = ref.object as? UserDefaults,
              let key = args.first?.stringValue else { return .int(0) }
        return .int(defaults.integer(forKey: key))
    }

    // bool(forKey:)
    registry.registerMethod(typeName: "UserDefaults", selector: "bool", parameterLabels: ["forKey"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let defaults = ref.object as? UserDefaults,
              let key = args.first?.stringValue else { return .bool(false) }
        return .bool(defaults.bool(forKey: key))
    }

    // removeObject(forKey:)
    registry.registerMethod(typeName: "UserDefaults", selector: "removeObject", parameterLabels: ["forKey"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let defaults = ref.object as? UserDefaults,
              let key = args.first?.stringValue else { return .void }
        defaults.removeObject(forKey: key)
        return .void
    }
}
