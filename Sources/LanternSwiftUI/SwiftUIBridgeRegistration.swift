#if canImport(SwiftUI)
import SwiftUI
import LanternVM
import LanternBridge

/// Registers SwiftUI view types, modifiers, and state management in a BridgeRegistry.
/// The VM is needed for container types that invoke trailing closures.
public func registerSwiftUIBridge(on registry: BridgeRegistry, vm: VM? = nil) {
    // MARK: - Leaf View Constructors

    registry.registerType("Text") { args in
        let text = args.first?.stringValue ?? ""
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(Text(text))), typeName: "Text"))
    }

    registry.registerType("Spacer") { _ in
        .hostObject(HostObjectRef(object: ViewBox(AnyView(Spacer())), typeName: "Spacer"))
    }

    registry.registerType("Divider") { _ in
        .hostObject(HostObjectRef(object: ViewBox(AnyView(Divider())), typeName: "Divider"))
    }

    registry.registerType("Image") { args in
        let name = args.first?.stringValue ?? ""
        // Two-arg form: Image(systemName: "star") — first arg is name string
        // One-arg form: Image("photo") — asset name
        // For now, default to systemName (SF Symbols) since that's most common in prototyping
        let view = AnyView(Image(systemName: name))
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
        if args.count >= 3,
           let r = args[0].doubleValue, let g = args[1].doubleValue, let b = args[2].doubleValue {
            let color = Color(red: r, green: g, blue: b)
            return .hostObject(HostObjectRef(object: ViewBox(AnyView(color)), typeName: "Color"))
        }
        let name = args.first?.stringValue ?? "clear"
        let color = namedColor(name) ?? .clear
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(color)), typeName: "Color"))
    }

    for name in ["red", "blue", "green", "yellow", "orange", "purple", "pink",
                  "white", "black", "gray", "clear", "primary", "secondary"] {
        if let color = namedColor(name) {
            registry.registerStaticProperty(typeName: "Color", name: name, getter: {
                .hostObject(HostObjectRef(object: ViewBox(AnyView(color)), typeName: "Color"))
            }, setter: nil)
        }
    }

    // MARK: - Container View Constructors (need VM for trailing closures)

    if let vm = vm {
        registerContainerTypes(on: registry, vm: vm)
        registerButton(on: registry, vm: vm)
    }

    // MARK: - Modifier Methods

    let modifierNames = [
        "padding", "frame", "font", "bold", "italic", "underline",
        "foregroundColor", "foregroundStyle", "background", "overlay",
        "opacity", "cornerRadius", "shadow", "border", "hidden",
        "disabled", "navigationTitle", "rotationEffect", "scaleEffect",
        "lineLimit", "fixedSize", "offset", "clipShape", "strikethrough",
        "multilineTextAlignment", "listStyle", "animation"
    ]

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

// MARK: - Container Types

private func registerContainerTypes(on registry: BridgeRegistry, vm: VM) {
    let containerTypes = ["VStack", "HStack", "ZStack", "ScrollView", "Group", "List", "NavigationStack"]

    for typeName in containerTypes {
        registry.registerType(typeName) { [weak vm] args in
            guard let vm else { return .nil_ }
            var spacing: Value? = nil
            var closureArg: Value? = nil

            for arg in args {
                switch arg {
                case .closure: closureArg = arg
                case .int, .double: spacing = arg
                default: break
                }
            }

            // Invoke trailing closure with a ViewCollector to gather ALL child views.
            // The VM's pop opcode intercepts ViewBox values when a collector is active.
            let collector = ViewCollector()
            var childBox = ViewBox(AnyView(EmptyView()))
            if let closure = closureArg {
                // Set up context with collector
                let savedContext = vm.swiftUIContext
                let stateStore = savedContext?.stateStore ?? DummyStateStore()
                vm.swiftUIContext = SwiftUIContext(stateStore: stateStore, viewCollector: collector)

                let result = try vm.invokeValue(closure, args: [])

                // Restore context
                vm.swiftUIContext = savedContext

                // The closure's return value (last expression) is also a view
                if case .hostObject(let ref) = result, let box = ref.object as? ViewBox {
                    collector.views.append(box.view)
                }

                // Build combined view from all collected children
                childBox = ViewBox(collector.buildCombinedView())
            }

            let spacingValue = spacing?.doubleValue.map { CGFloat($0) }
            let containerView: AnyView
            switch typeName {
            case "VStack":
                containerView = AnyView(VStack(spacing: spacingValue ?? 8) { childBox.view })
            case "HStack":
                containerView = AnyView(HStack(spacing: spacingValue ?? 8) { childBox.view })
            case "ZStack":
                containerView = AnyView(ZStack { childBox.view })
            case "ScrollView":
                containerView = AnyView(ScrollView { childBox.view })
            case "Group":
                containerView = AnyView(Group { childBox.view })
            case "List":
                containerView = AnyView(List { childBox.view })
            case "NavigationStack":
                containerView = AnyView(NavigationStack { childBox.view })
            default:
                containerView = AnyView(childBox.view)
            }

            return .hostObject(HostObjectRef(object: ViewBox(containerView), typeName: typeName))
        }
    }
}

// MARK: - Button

private func registerButton(on registry: BridgeRegistry, vm: VM) {
    registry.registerType("Button") { [weak vm] args in
        guard let vm else { return .nil_ }
        var title: String? = nil
        var actionClosure: Value? = nil
        var labelClosure: Value? = nil

        for arg in args {
            switch arg {
            case .string(let s):
                title = s
            case .closure:
                if actionClosure == nil {
                    actionClosure = arg
                } else {
                    labelClosure = arg
                }
            default:
                break
            }
        }

        let action: () -> Void = {
            if let actionClosure {
                _ = try? vm.invokeValue(actionClosure, args: [])
            }
        }

        let view: AnyView
        if let title {
            view = AnyView(Button(title, action: action))
        } else if let labelClosure {
            var labelView = AnyView(EmptyView())
            if let result = try? vm.invokeValue(labelClosure, args: []),
               case .hostObject(let ref) = result, let box = ref.object as? ViewBox {
                labelView = box.view
            }
            view = AnyView(Button(action: action) { labelView })
        } else {
            view = AnyView(Button("", action: action))
        }

        return .hostObject(HostObjectRef(object: ViewBox(view), typeName: "Button"))
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

/// Minimal StateStoreProtocol for container closures invoked outside a ViewStub context.
private final class DummyStateStore: StateStoreProtocol {
    func get(_ name: String) -> Value { .nil_ }
    func set(_ name: String, _ value: Value) {}
    func contains(_ name: String) -> Bool { false }
}
#endif
