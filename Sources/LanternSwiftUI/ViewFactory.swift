#if canImport(SwiftUI)
import SwiftUI
import LanternVM

/// Converts runtime Value results into SwiftUI AnyViews.
/// Used by ViewStub to render the result of evaluating an interpreted view body.
/// View construction itself happens via BridgeRegistry (SwiftUIBridgeRegistration).
public struct ViewFactory {

    /// Convert a runtime Value (from evaluating a view body) into an AnyView.
    public static func viewFromValue(_ value: Value) -> AnyView {
        switch value {
        case .hostObject(let ref) where ref.object is ViewBox:
            return (ref.object as! ViewBox).view
        case .string(let text):
            return AnyView(Text(text))
        case .int(let n):
            return AnyView(Text("\(n)"))
        case .double(let d):
            return AnyView(Text("\(d)"))
        case .bool(let b):
            return AnyView(Text("\(b)"))
        case .void, .nil_:
            return AnyView(EmptyView())
        default:
            return AnyView(Text(value.description))
        }
    }

    /// Build a ViewDescriptor from a runtime Value for debugger inspection.
    public static func descriptorFromValue(_ value: Value, location: SourceLocation = .unknown) -> ViewDescriptor {
        switch value {
        case .hostObject(let ref) where ref.object is ViewBox:
            return ViewDescriptor(typeName: ref.typeName, properties: [:], modifiers: [],
                                  children: [], sourceLocation: location)
        case .string(let text):
            return ViewDescriptor(typeName: "Text", properties: ["text": .string(text)], modifiers: [],
                                  children: [], sourceLocation: location)
        default:
            return ViewDescriptor(typeName: "Unknown", properties: [:], modifiers: [],
                                  children: [], sourceLocation: location)
        }
    }
}
#endif
