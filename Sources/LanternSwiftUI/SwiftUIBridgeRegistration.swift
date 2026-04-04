#if canImport(SwiftUI)
import SwiftUI
import LanternVM
import LanternBridge

/// Registers SwiftUI view types, modifiers, and state management in a BridgeRegistry.
public func registerSwiftUIBridge(on registry: BridgeRegistry) {
    // MARK: - View Constructors

    registry.registerType("Text") { args in
        let text = args.first?.stringValue ?? ""
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(Text(text))), typeName: "Text"))
    }

    registry.registerType("Spacer") { _ in
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(Spacer())), typeName: "Spacer"))
    }

    registry.registerType("Divider") { _ in
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(Divider())), typeName: "Divider"))
    }

    registry.registerType("Image") { args in
        let name = args.first?.stringValue ?? ""
        let view: AnyView
        // If label is "systemName", use SF Symbols
        if args.count >= 2 {
            view = AnyView(Image(systemName: name))
        } else {
            view = AnyView(Image(systemName: name))
        }
        return .hostObject(HostObjectRef(object: ViewBox(view), typeName: "Image"))
    }

    registry.registerType("Label") { args in
        let title = args.first?.stringValue ?? ""
        let systemImage = args.count > 1 ? args[1].stringValue ?? "" : "star"
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(Label(title, systemImage: systemImage))), typeName: "Label"))
    }

    registry.registerType("ProgressView") { args in
        let view: AnyView
        if let value = args.first?.doubleValue {
            view = AnyView(ProgressView(value: value))
        } else {
            view = AnyView(ProgressView())
        }
        return .hostObject(HostObjectRef(object: ViewBox(view), typeName: "ProgressView"))
    }

    // MARK: - Color

    registry.registerType("Color") { args in
        let name = args.first?.stringValue ?? "clear"
        let color = namedColor(name) ?? .clear
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(color)), typeName: "Color"))
    }

    // Register named color constants
    for name in ["red", "blue", "green", "yellow", "orange", "purple", "pink",
                  "white", "black", "gray", "clear", "primary", "secondary"] {
        if let color = namedColor(name) {
            registry.registerStaticProperty(typeName: "Color", name: name, getter: {
                .hostObject(HostObjectRef(object: ViewBox(AnyView(color)), typeName: "Color"))
            }, setter: nil)
        }
    }

    // MARK: - Modifier Methods (applied to any view host object)

    let modifierNames = [
        "padding", "frame", "font", "bold", "italic", "underline",
        "foregroundColor", "foregroundStyle", "background", "overlay",
        "opacity", "cornerRadius", "shadow", "border", "hidden",
        "disabled", "navigationTitle", "rotationEffect", "scaleEffect",
        "lineLimit", "fixedSize", "offset", "clipShape", "strikethrough",
        "multilineTextAlignment", "listStyle", "animation"
    ]

    // Register modifiers as methods on a generic "View" type
    // The bridge dispatch will forward these to ModifierApplicator
    for modName in modifierNames {
        registry.registerMethod(typeName: "View", selector: modName, parameterLabels: []) { receiver, args in
            guard let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox else {
                return receiver
            }
            let (modified, _) = ModifierApplicator.apply(modName, arguments: args, to: box.view)
            return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
        }
    }
}

// MARK: - Helpers

/// Box to hold an AnyView inside a HostObjectRef (which requires AnyObject).
public final class ViewBox: @unchecked Sendable {
    public let view: AnyView
    public init(_ view: AnyView) { self.view = view }
}

private func namedColor(_ name: String) -> Color? {
    switch name.lowercased() {
    case "red": return .red
    case "blue": return .blue
    case "green": return .green
    case "yellow": return .yellow
    case "orange": return .orange
    case "purple": return .purple
    case "pink": return .pink
    case "white": return .white
    case "black": return .black
    case "gray", "grey": return .gray
    case "clear": return .clear
    case "primary": return .primary
    case "secondary": return .secondary
    default: return nil
    }
}
#endif
