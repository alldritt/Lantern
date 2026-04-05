import Foundation
import LanternVM

/// Bridge registration for NumberFormatter.
public func registerNumberFormatterBridge(on registry: BridgeRegistry) {
    // NumberFormatter()
    registry.registerType("NumberFormatter") { _ in
        .hostObject(HostObjectRef(object: NumberFormatter(), typeName: "NumberFormatter"))
    }

    // numberStyle
    registry.registerProperty(typeName: "NumberFormatter", name: "numberStyle", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? NumberFormatter else { return .nil_ }
        return .int(Int(fmt.numberStyle.rawValue))
    }, setter: { receiver, value in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? NumberFormatter,
              let raw = value.intValue, let style = NumberFormatter.Style(rawValue: UInt(raw)) else { return }
        fmt.numberStyle = style
    })

    // minimumFractionDigits / maximumFractionDigits
    registry.registerProperty(typeName: "NumberFormatter", name: "minimumFractionDigits", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? NumberFormatter else { return .int(0) }
        return .int(fmt.minimumFractionDigits)
    }, setter: { receiver, value in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? NumberFormatter,
              let v = value.intValue else { return }
        fmt.minimumFractionDigits = v
    })

    registry.registerProperty(typeName: "NumberFormatter", name: "maximumFractionDigits", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? NumberFormatter else { return .int(0) }
        return .int(fmt.maximumFractionDigits)
    }, setter: { receiver, value in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? NumberFormatter,
              let v = value.intValue else { return }
        fmt.maximumFractionDigits = v
    })

    // currencyCode
    registry.registerProperty(typeName: "NumberFormatter", name: "currencyCode", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? NumberFormatter else { return .nil_ }
        return .string(fmt.currencyCode ?? "")
    }, setter: { receiver, value in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? NumberFormatter,
              let code = value.stringValue else { return }
        fmt.currencyCode = code
    })

    // string(from:)
    registry.registerMethod(typeName: "NumberFormatter", selector: "string", parameterLabels: ["from"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? NumberFormatter else { return .nil_ }
        if let intVal = args.first?.intValue {
            return fmt.string(from: NSNumber(value: intVal)).map { .string($0) } ?? .nil_
        }
        if let dblVal = args.first?.doubleValue {
            return fmt.string(from: NSNumber(value: dblVal)).map { .string($0) } ?? .nil_
        }
        return .nil_
    }

    // number(from:)
    registry.registerMethod(typeName: "NumberFormatter", selector: "number", parameterLabels: ["from"]) { receiver, args in
        guard let ref = receiver.hostObjectRef, let fmt = ref.object as? NumberFormatter,
              let str = args.first?.stringValue else { return .nil_ }
        if let num = fmt.number(from: str) {
            return .double(num.doubleValue)
        }
        return .nil_
    }
}
