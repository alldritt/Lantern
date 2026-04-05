import Foundation
import LanternVM

/// Bridge registration for DateFormatter and Date formatting.
public func registerDateFormatterBridge(on registry: BridgeRegistry) {
    // DateFormatter()
    registry.registerType("DateFormatter") { _ in
        .hostObject(HostObjectRef(object: DateFormatter(), typeName: "DateFormatter"))
    }

    // dateFormat property
    registry.registerProperty(typeName: "DateFormatter", name: "dateFormat", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? DateFormatter else { return .nil_ }
        return .string(fmt.dateFormat ?? "")
    }, setter: { receiver, value in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? DateFormatter,
              let format = value.stringValue else { return }
        fmt.dateFormat = format
    })

    // dateStyle property
    registry.registerProperty(typeName: "DateFormatter", name: "dateStyle", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? DateFormatter else { return .nil_ }
        return .int(Int(fmt.dateStyle.rawValue))
    }, setter: { receiver, value in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? DateFormatter,
              let raw = value.intValue, let style = DateFormatter.Style(rawValue: UInt(raw)) else { return }
        fmt.dateStyle = style
    })

    // timeStyle property
    registry.registerProperty(typeName: "DateFormatter", name: "timeStyle", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? DateFormatter else { return .nil_ }
        return .int(Int(fmt.timeStyle.rawValue))
    }, setter: { receiver, value in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? DateFormatter,
              let raw = value.intValue, let style = DateFormatter.Style(rawValue: UInt(raw)) else { return }
        fmt.timeStyle = style
    })

    // locale property
    registry.registerProperty(typeName: "DateFormatter", name: "locale", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? DateFormatter else { return .nil_ }
        return .string(fmt.locale.identifier)
    }, setter: nil)

    // string(from:)
    registry.registerMethod(typeName: "DateFormatter", selector: "string", parameterLabels: ["from"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? DateFormatter,
              let dateRef = args.first?.hostObjectRef, let date = dateRef.object as? NSDate else { return .nil_ }
        return .string(fmt.string(from: date as Date))
    }

    // date(from:)
    registry.registerMethod(typeName: "DateFormatter", selector: "date", parameterLabels: ["from"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? DateFormatter,
              let str = args.first?.stringValue else { return .nil_ }
        if let date = fmt.date(from: str) {
            return .hostObject(HostObjectRef(object: date as NSDate, typeName: "Date"))
        }
        return .nil_
    }
}
