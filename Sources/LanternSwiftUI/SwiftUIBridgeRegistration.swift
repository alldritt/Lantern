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

    // MARK: - Binding-Aware Views

    registerBindingViews(on: registry)

    // MARK: - Container + Interactive Views (need VM)

    if let vm = vm {
        registerContainerTypes(on: registry, vm: vm)
        registerButton(on: registry, vm: vm)
        registerForEach(on: registry, vm: vm)
        registerSheetModifier(on: registry, vm: vm)
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

    // MARK: - Lifecycle Modifiers (need VM for closure invocation)

    if let vm = vm {
        registerLifecycleModifiers(on: registry, vm: vm)
    }
}

// MARK: - Lifecycle Modifiers

private func registerLifecycleModifiers(on registry: BridgeRegistry, vm: VM) {
    registry.registerMethod(typeName: "View", selector: "onAppear", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox,
              let closure = args.first else { return receiver }
        let modified = AnyView(box.view.onAppear { _ = try? vm.invokeValue(closure, args: []) })
        return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
    }

    registry.registerMethod(typeName: "View", selector: "onDisappear", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox,
              let closure = args.first else { return receiver }
        let modified = AnyView(box.view.onDisappear { _ = try? vm.invokeValue(closure, args: []) })
        return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
    }

    registry.registerMethod(typeName: "View", selector: "onTapGesture", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox,
              let closure = args.first else { return receiver }
        let modified = AnyView(box.view.onTapGesture { _ = try? vm.invokeValue(closure, args: []) })
        return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
    }
}

// MARK: - Binding-Aware Views

private func registerBindingViews(on registry: BridgeRegistry) {
    registry.registerType("Toggle") { args in
        // Toggle("Label", isOn: $binding)
        let title = args.first(where: { $0.stringValue != nil })?.stringValue ?? ""
        // Find the binding argument
        if let bindingArg = args.first(where: { isBindingRef($0) }),
           let bindingRef = extractBindingRef(bindingArg) {
            let binding = Binding<Bool>(
                get: { bindingRef.stateStore.get(bindingRef.key).boolValue ?? false },
                set: { bindingRef.stateStore.set(bindingRef.key, .bool($0)) }
            )
            return .hostObject(HostObjectRef(object: ViewBox(AnyView(Toggle(title, isOn: binding))), typeName: "Toggle"))
        }
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(Toggle(title, isOn: .constant(false)))), typeName: "Toggle"))
    }

    registry.registerType("TextField") { args in
        // TextField("Placeholder", text: $binding)
        let title = args.first?.stringValue ?? ""
        if args.count >= 2, let bindingRef = extractBindingRef(args[1]) {
            let binding = Binding<String>(
                get: { bindingRef.stateStore.get(bindingRef.key).stringValue ?? "" },
                set: { bindingRef.stateStore.set(bindingRef.key, .string($0)) }
            )
            return .hostObject(HostObjectRef(object: ViewBox(AnyView(TextField(title, text: binding))), typeName: "TextField"))
        }
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(TextField(title, text: .constant("")))), typeName: "TextField"))
    }

    registry.registerType("TextEditor") { args in
        if let bindingRef = extractBindingRef(args.first ?? .nil_) {
            let binding = Binding<String>(
                get: { bindingRef.stateStore.get(bindingRef.key).stringValue ?? "" },
                set: { bindingRef.stateStore.set(bindingRef.key, .string($0)) }
            )
            return .hostObject(HostObjectRef(object: ViewBox(AnyView(TextEditor(text: binding))), typeName: "TextEditor"))
        }
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(TextEditor(text: .constant("")))), typeName: "TextEditor"))
    }

    registry.registerType("Slider") { args in
        // Slider(value: $binding, in: 0...100)
        if let bindingRef = extractBindingRef(args.first ?? .nil_) {
            let binding = Binding<Double>(
                get: { bindingRef.stateStore.get(bindingRef.key).doubleValue ?? 0 },
                set: { bindingRef.stateStore.set(bindingRef.key, .double($0)) }
            )
            let range: ClosedRange<Double>
            if args.count >= 2, case .range(let lo, let hi, _) = args[1] {
                range = Double(lo)...Double(hi)
            } else {
                range = 0...1
            }
            return .hostObject(HostObjectRef(object: ViewBox(AnyView(Slider(value: binding, in: range))), typeName: "Slider"))
        }
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(Slider(value: .constant(0.5)))), typeName: "Slider"))
    }
}

private func isBindingRef(_ value: Value) -> Bool {
    if case .hostObject(let ref) = value, ref.object is BindingRef { return true }
    return false
}

private func extractBindingRef(_ value: Value) -> BindingRef? {
    if case .hostObject(let ref) = value, let binding = ref.object as? BindingRef {
        return binding
    }
    return nil
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

// MARK: - ForEach

private func registerForEach(on registry: BridgeRegistry, vm: VM) {
    registry.registerType("ForEach") { [weak vm] args in
        guard let vm else { return .nil_ }
        // ForEach(items) { item in ... } — args: [array, closure]
        guard args.count >= 2,
              case .array(let items) = args[0],
              let closure = args.last else { return .nil_ }

        var childViews: [AnyView] = []
        for item in items {
            let result = try vm.invokeValue(closure, args: [item])
            if case .hostObject(let ref) = result, let box = ref.object as? ViewBox {
                childViews.append(box.view)
            }
        }

        let combined = AnyView(
            ForEach(Array(childViews.enumerated()), id: \.offset) { _, view in view }
        )
        return .hostObject(HostObjectRef(object: ViewBox(combined), typeName: "ForEach"))
    }
}

// MARK: - Sheet Modifier

private func registerSheetModifier(on registry: BridgeRegistry, vm: VM) {
    registry.registerMethod(typeName: "View", selector: "sheet", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox else {
            return receiver
        }
        // .sheet(isPresented: $binding) { content }
        let bindingRef = args.compactMap { extractBindingRef($0) }.first
        let contentClosure = args.first(where: { if case .closure = $0 { return true }; return false })

        if let bindingRef, let contentClosure {
            let binding = Binding<Bool>(
                get: { bindingRef.stateStore.get(bindingRef.key).boolValue ?? false },
                set: { bindingRef.stateStore.set(bindingRef.key, .bool($0)) }
            )
            let modified = AnyView(box.view.sheet(isPresented: binding) {
                if let result = try? vm.invokeValue(contentClosure, args: []),
                   case .hostObject(let ref) = result, let contentBox = ref.object as? ViewBox {
                    contentBox.view
                } else {
                    EmptyView()
                }
            })
            return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
        }
        return receiver
    }

    // .alert(title, isPresented: $binding) { actions }
    registry.registerMethod(typeName: "View", selector: "alert", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox else {
            return receiver
        }
        let title = args.first(where: { $0.stringValue != nil })?.stringValue ?? ""
        let bindingRef = args.compactMap { extractBindingRef($0) }.first
        let actionClosure = args.first(where: { if case .closure = $0 { return true }; return false })

        if let bindingRef {
            let binding = Binding<Bool>(
                get: { bindingRef.stateStore.get(bindingRef.key).boolValue ?? false },
                set: { bindingRef.stateStore.set(bindingRef.key, .bool($0)) }
            )
            let modified = AnyView(box.view.alert(title, isPresented: binding) {
                if let actionClosure, let result = try? vm.invokeValue(actionClosure, args: []),
                   case .hostObject(let ref) = result, let actionBox = ref.object as? ViewBox {
                    actionBox.view
                } else {
                    Button("OK") { bindingRef.stateStore.set(bindingRef.key, .bool(false)) }
                }
            })
            return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
        }
        return receiver
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
