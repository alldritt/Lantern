import Foundation
import LanternVM

/// Bridge registration for Foundation Date type.
public func registerDateBridge(on registry: BridgeRegistry) {
    // Date() — current date
    registry.registerType("Date") { args in
        if let interval = args.first?.doubleValue {
            return .hostObject(HostObjectRef(object: NSDate(timeIntervalSince1970: interval), typeName: "Date"))
        }
        return .hostObject(HostObjectRef(object: NSDate(), typeName: "Date"))
    }

    // Properties
    registry.registerProperty(typeName: "Date", name: "timeIntervalSince1970", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let date = ref.object as? NSDate else { return .nil_ }
        return .double(date.timeIntervalSince1970)
    }, setter: nil)

    registry.registerProperty(typeName: "Date", name: "timeIntervalSinceNow", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let date = ref.object as? NSDate else { return .nil_ }
        return .double(date.timeIntervalSinceNow)
    }, setter: nil)

    // Methods
    registry.registerMethod(typeName: "Date", selector: "addingTimeInterval", parameterLabels: ["_"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let date = ref.object as? NSDate,
              let interval = args.first?.doubleValue else { return receiver }
        let newDate = date.addingTimeInterval(interval)
        return .hostObject(HostObjectRef(object: newDate as NSDate, typeName: "Date"))
    }

    registry.registerMethod(typeName: "Date", selector: "timeIntervalSince", parameterLabels: ["_"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let date = ref.object as? NSDate,
              let otherRef = args.first?.hostObjectRef, let other = otherRef.object as? NSDate else { return .nil_ }
        return .double(date.timeIntervalSince(other as Date))
    }
}
