import Foundation
import LanternVM

/// Bridge registration for Bundle.
public func registerBundleBridge(on registry: BridgeRegistry) {
    // Bundle.main
    registry.registerStaticProperty(typeName: "Bundle", name: "main", getter: {
        .hostObject(HostObjectRef(object: Bundle.main, typeName: "Bundle"))
    }, setter: nil)

    // infoDictionary
    registry.registerProperty(typeName: "Bundle", name: "infoDictionary", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let bundle = ref.object as? Bundle,
              let info = bundle.infoDictionary else { return .nil_ }
        var dict: [String: Value] = [:]
        for (key, value) in info {
            if let s = value as? String { dict[key] = .string(s) }
            else if let n = value as? NSNumber { dict[key] = .double(n.doubleValue) }
            else { dict[key] = .string("\(value)") }
        }
        return .dictionary(dict)
    }, setter: nil)

    // bundleIdentifier
    registry.registerProperty(typeName: "Bundle", name: "bundleIdentifier", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let bundle = ref.object as? Bundle else { return .nil_ }
        return bundle.bundleIdentifier.map { .string($0) } ?? .nil_
    }, setter: nil)

    // url(forResource:withExtension:)
    registry.registerMethod(typeName: "Bundle", selector: "url", parameterLabels: ["forResource", "withExtension"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let bundle = ref.object as? Bundle,
              args.count >= 2,
              let resource = args[0].stringValue,
              let ext = args[1].stringValue else { return .nil_ }
        if let url = bundle.url(forResource: resource, withExtension: ext) {
            return .optional(.hostObject(HostObjectRef(object: url as NSURL, typeName: "URL")))
        }
        return .nil_
    }

    // path(forResource:ofType:)
    registry.registerMethod(typeName: "Bundle", selector: "path", parameterLabels: ["forResource", "ofType"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let bundle = ref.object as? Bundle,
              args.count >= 2,
              let resource = args[0].stringValue,
              let type = args[1].stringValue else { return .nil_ }
        return bundle.path(forResource: resource, ofType: type).map { .string($0) } ?? .nil_
    }
}
