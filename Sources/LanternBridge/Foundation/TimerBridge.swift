import Foundation
import LanternVM

/// Bridge registration for Timer.
public func registerTimerBridge(on registry: BridgeRegistry) {
    // Timer.scheduledTimer(withTimeInterval:repeats:block:)
    registry.registerStaticMethod(typeName: "Timer", selector: "scheduledTimer",
                                  parameterLabels: ["withTimeInterval", "repeats", "block"]) { args in
        guard args.count >= 2,
              let interval = args[0].doubleValue,
              let repeats = args[1].boolValue else { return .nil_ }
        // The closure arg would be the third argument — but invoking it
        // requires VM access which we don't have in a static method.
        // For now, create the timer without the block (placeholder).
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            // VM closure invocation would go here
        }
        return .hostObject(HostObjectRef(object: timer, typeName: "Timer"))
    }

    // invalidate()
    registry.registerMethod(typeName: "Timer", selector: "invalidate", parameterLabels: []) { receiver, _ in
        if let ref = receiver.hostObjectRef, let timer = ref.object as? Timer {
            timer.invalidate()
        }
        return .void
    }

    // isValid
    registry.registerProperty(typeName: "Timer", name: "isValid", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let timer = ref.object as? Timer else { return .bool(false) }
        return .bool(timer.isValid)
    }, setter: nil)

    // timeInterval
    registry.registerProperty(typeName: "Timer", name: "timeInterval", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let timer = ref.object as? Timer else { return .double(0) }
        return .double(timer.timeInterval)
    }, setter: nil)
}
