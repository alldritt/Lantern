import Foundation
import LanternVM

/// Bridge registration for Foundation URL type.
public func registerURLBridge(on registry: BridgeRegistry) {
    // URL(string:)
    registry.registerType("URL") { args in
        guard let str = args.first?.stringValue, let url = URL(string: str) else { return .nil_ }
        return .hostObject(HostObjectRef(object: url as NSURL, typeName: "URL"))
    }

    // Properties
    registry.registerProperty(typeName: "URL", name: "absoluteString", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let url = ref.object as? NSURL else { return .nil_ }
        return .string(url.absoluteString ?? "")
    }, setter: nil)

    registry.registerProperty(typeName: "URL", name: "host", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let url = ref.object as? NSURL else { return .nil_ }
        return url.host.map { .string($0) } ?? .nil_
    }, setter: nil)

    registry.registerProperty(typeName: "URL", name: "path", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let url = ref.object as? NSURL else { return .nil_ }
        return .string(url.path ?? "")
    }, setter: nil)

    registry.registerProperty(typeName: "URL", name: "lastPathComponent", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let url = ref.object as? NSURL else { return .nil_ }
        return .string(url.lastPathComponent ?? "")
    }, setter: nil)

    registry.registerProperty(typeName: "URL", name: "pathExtension", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let url = ref.object as? NSURL else { return .nil_ }
        return .string(url.pathExtension ?? "")
    }, setter: nil)

    registry.registerProperty(typeName: "URL", name: "scheme", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let url = ref.object as? NSURL else { return .nil_ }
        return url.scheme.map { .string($0) } ?? .nil_
    }, setter: nil)

    // Methods
    registry.registerMethod(typeName: "URL", selector: "appendingPathComponent", parameterLabels: ["_"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let url = ref.object as? NSURL,
              let component = args.first?.stringValue,
              let newURL = (url as URL).appendingPathComponent(component) as NSURL? else { return receiver }
        return .hostObject(HostObjectRef(object: newURL, typeName: "URL"))
    }
}
