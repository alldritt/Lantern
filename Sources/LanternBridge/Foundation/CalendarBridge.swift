import Foundation
import LanternVM

/// Bridge registration for Calendar and DateComponents.
public func registerCalendarBridge(on registry: BridgeRegistry) {
    // MARK: - Calendar

    // Calendar.current
    registry.registerStaticProperty(typeName: "Calendar", name: "current", getter: {
        .hostObject(HostObjectRef(object: Calendar.current as NSCalendar, typeName: "Calendar"))
    }, setter: nil)

    // dateComponents(_:from:)
    registry.registerMethod(typeName: "Calendar", selector: "dateComponents", parameterLabels: ["_", "from"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let cal = ref.object as? NSCalendar,
              let dateRef = args.last?.hostObjectRef, let date = dateRef.object as? NSDate else { return .nil_ }
        let components = (cal as Calendar).dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date as Date)
        return dateComponentsToValue(components)
    }

    // date(byAdding:value:to:)
    registry.registerMethod(typeName: "Calendar", selector: "date", parameterLabels: ["byAdding", "value", "to"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let cal = ref.object as? NSCalendar,
              args.count >= 3,
              let componentName = args[0].stringValue,
              let value = args[1].intValue,
              let dateRef = args[2].hostObjectRef, let date = dateRef.object as? NSDate else { return .nil_ }
        let component = calendarComponent(from: componentName)
        if let result = (cal as Calendar).date(byAdding: component, value: value, to: date as Date) {
            return .optional(.hostObject(HostObjectRef(object: result as NSDate, typeName: "Date")))
        }
        return .nil_
    }

    // startOfDay(for:)
    registry.registerMethod(typeName: "Calendar", selector: "startOfDay", parameterLabels: ["for"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let cal = ref.object as? NSCalendar,
              let dateRef = args.first?.hostObjectRef, let date = dateRef.object as? NSDate else { return .nil_ }
        let start = (cal as Calendar).startOfDay(for: date as Date)
        return .hostObject(HostObjectRef(object: start as NSDate, typeName: "Date"))
    }

    // isDateInToday/isDateInWeekend
    registry.registerMethod(typeName: "Calendar", selector: "isDateInToday", parameterLabels: ["_"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let cal = ref.object as? NSCalendar,
              let dateRef = args.first?.hostObjectRef, let date = dateRef.object as? NSDate else { return .bool(false) }
        return .bool((cal as Calendar).isDateInToday(date as Date))
    }

    registry.registerMethod(typeName: "Calendar", selector: "isDateInWeekend", parameterLabels: ["_"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let cal = ref.object as? NSCalendar,
              let dateRef = args.first?.hostObjectRef, let date = dateRef.object as? NSDate else { return .bool(false) }
        return .bool((cal as Calendar).isDateInWeekend(date as Date))
    }

    // MARK: - DateComponents

    registry.registerType("DateComponents") { args in
        var dc = DateComponents()
        // Accept named values via dictionary-style args
        // In practice, properties are set individually
        return .hostObject(HostObjectRef(object: dc as NSDateComponents, typeName: "DateComponents"))
    }

    for (name, keyPath) in dateComponentFields() {
        registry.registerProperty(typeName: "DateComponents", name: name, getter: { receiver in
            guard let ref = receiver.hostObjectRef, let dc = ref.object as? NSDateComponents else { return .nil_ }
            let val = (dc as DateComponents).value(for: calendarComponent(from: name))
            return val.map { .int($0) } ?? .nil_
        }, setter: { receiver, value in
            guard let ref = receiver.hostObjectRef, let dc = ref.object as? NSDateComponents,
                  let v = value.intValue else { return }
            // Set directly via known property name
            switch name {
            case "year": dc.year = v
            case "month": dc.month = v
            case "day": dc.day = v
            case "hour": dc.hour = v
            case "minute": dc.minute = v
            case "second": dc.second = v
            case "weekday": dc.weekday = v
            default: break
            }
        })
    }
}

// MARK: - Helpers

private func dateComponentsToValue(_ dc: DateComponents) -> Value {
    var dict: [String: Value] = [:]
    if let v = dc.year { dict["year"] = .int(v) }
    if let v = dc.month { dict["month"] = .int(v) }
    if let v = dc.day { dict["day"] = .int(v) }
    if let v = dc.hour { dict["hour"] = .int(v) }
    if let v = dc.minute { dict["minute"] = .int(v) }
    if let v = dc.second { dict["second"] = .int(v) }
    if let v = dc.weekday { dict["weekday"] = .int(v) }
    return .dictionary(dict)
}

private func calendarComponent(from name: String) -> Calendar.Component {
    switch name {
    case "year": return .year
    case "month": return .month
    case "day": return .day
    case "hour": return .hour
    case "minute": return .minute
    case "second": return .second
    case "weekday": return .weekday
    case "weekOfYear": return .weekOfYear
    default: return .day
    }
}

private func dateComponentFields() -> [(String, String)] {
    [("year", "year"), ("month", "month"), ("day", "day"),
     ("hour", "hour"), ("minute", "minute"), ("second", "second"),
     ("weekday", "weekday")]
}
