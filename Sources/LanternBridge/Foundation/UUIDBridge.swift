import Foundation
import LanternVM

/// Bridge registration for Foundation UUID type.
public func registerUUIDBridge(on registry: BridgeRegistry) {
    // UUID()
    registry.registerType("UUID") { _ in
        let uuid = UUID()
        return .hostObject(HostObjectRef(object: uuid as NSUUID, typeName: "UUID"))
    }

    // Properties
    registry.registerProperty(typeName: "UUID", name: "uuidString", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let uuid = ref.object as? NSUUID else { return .nil_ }
        return .string(uuid.uuidString)
    }, setter: nil)
}
