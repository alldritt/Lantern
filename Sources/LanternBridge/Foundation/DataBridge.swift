import Foundation
import LanternVM

/// Bridge registration for Data.
public func registerDataBridge(on registry: BridgeRegistry) {
    // Data()
    registry.registerType("Data") { args in
        if let str = args.first?.stringValue {
            let data = str.data(using: .utf8) ?? Data()
            return .hostObject(HostObjectRef(object: data as NSData, typeName: "Data"))
        }
        return .hostObject(HostObjectRef(object: NSData(), typeName: "Data"))
    }

    // count
    registry.registerProperty(typeName: "Data", name: "count", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let data = ref.object as? NSData else { return .int(0) }
        return .int(data.count)
    }, setter: nil)

    // isEmpty
    registry.registerProperty(typeName: "Data", name: "isEmpty", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let data = ref.object as? NSData else { return .bool(true) }
        return .bool(data.count == 0)
    }, setter: nil)

    // base64EncodedString()
    registry.registerMethod(typeName: "Data", selector: "base64EncodedString", parameterLabels: []) { receiver, _ in
        guard let ref = receiver.hostObjectRef, let data = ref.object as? NSData else { return .string("") }
        return .string(data.base64EncodedString())
    }

    // String(data:encoding:) — add as a method on Data for convenience
    registry.registerMethod(typeName: "Data", selector: "string", parameterLabels: []) { receiver, _ in
        guard let ref = receiver.hostObjectRef, let data = ref.object as? NSData else { return .nil_ }
        return String(data: data as Data, encoding: .utf8).map { .string($0) } ?? .nil_
    }
}
