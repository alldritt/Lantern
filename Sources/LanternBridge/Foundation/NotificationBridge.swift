import Foundation
import LanternVM

/// Bridge registration for NotificationCenter.
public func registerNotificationBridge(on registry: BridgeRegistry) {
    // NotificationCenter.default
    registry.registerStaticProperty(typeName: "NotificationCenter", name: "default", getter: {
        .hostObject(HostObjectRef(object: NotificationCenter.default, typeName: "NotificationCenter"))
    }, setter: nil)

    // post(name:object:)
    registry.registerMethod(typeName: "NotificationCenter", selector: "post", parameterLabels: ["name", "object"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let center = ref.object as? NotificationCenter,
              let name = args.first?.stringValue else { return .void }
        center.post(name: Notification.Name(name), object: nil)
        return .void
    }

    // addObserver — simplified: takes name + closure
    // Returns an opaque observer token that can be used with removeObserver
    registry.registerMethod(typeName: "NotificationCenter", selector: "addObserver", parameterLabels: ["forName", "using"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let center = ref.object as? NotificationCenter,
              let name = args.first?.stringValue else { return .nil_ }
        // Note: closure invocation requires VM access which we don't have here.
        // Store the observer token for removal.
        let observer = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
            // Closure invocation would go here with VM access
        }
        return .hostObject(HostObjectRef(object: observer as AnyObject, typeName: "NSObjectProtocol"))
    }

    // removeObserver
    registry.registerMethod(typeName: "NotificationCenter", selector: "removeObserver", parameterLabels: ["_"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let center = ref.object as? NotificationCenter,
              let obsRef = args.first?.hostObjectRef else { return .void }
        center.removeObserver(obsRef.object)
        return .void
    }

    // Notification.Name convenience
    registry.registerType("Notification") { _ in .nil_ }
    registry.registerType("Notification.Name") { args in
        guard let name = args.first?.stringValue else { return .nil_ }
        return .string(name) // Store as string — used as key
    }
}
