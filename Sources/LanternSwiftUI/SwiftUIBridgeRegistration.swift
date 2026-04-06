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

    // MARK: - Additional Leaf Views

    registry.registerType("Link") { args in
        guard args.count >= 2, let title = args[0].stringValue, let urlStr = args[1].stringValue,
              let url = Foundation.URL(string: urlStr) else { return .nil_ }
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(Link(title, destination: url))), typeName: "Link"))
    }

    registry.registerType("Gauge") { args in
        let value = args.first?.doubleValue ?? 0.5
        let view = AnyView(Gauge(value: value) { EmptyView() })
        return .hostObject(HostObjectRef(object: ViewBox(view), typeName: "Gauge"))
    }

    registry.registerType("LabeledContent") { args in
        let label = args.first?.stringValue ?? ""
        let content = args.count > 1 ? args[1].stringValue ?? "" : ""
        let view = AnyView(LabeledContent(label, value: content))
        return .hostObject(HostObjectRef(object: ViewBox(view), typeName: "LabeledContent"))
    }

    // MARK: - Binding-Aware Views

    registerBindingViews(on: registry)

    // MARK: - Container + Interactive Views (need VM)

    if let vm = vm {
        registerContainerTypes(on: registry, vm: vm)
        registerButton(on: registry, vm: vm)
        registerForEach(on: registry, vm: vm)
        registerNavigationViews(on: registry, vm: vm)
        registerSheetModifier(on: registry, vm: vm)
        registerPresentationModifiers(on: registry, vm: vm)
        registerWithAnimation(on: registry, vm: vm)
        registerAdditionalViews(on: registry, vm: vm)
    }

    // MARK: - SwiftUI Enum-Like Type Constants
    //
    // Register static properties so implicit member syntax works:
    //   .font(.title)  →  Font.title
    //   .foregroundColor(.red)  →  Color.red
    //   .multilineTextAlignment(.center)  →  TextAlignment.center

    for (typeName, caseNames) in SwiftUIConstants.enumTypes {
        for caseName in caseNames {
            let tn = typeName
            let cn = caseName
            registry.registerStaticProperty(typeName: tn, name: cn, getter: {
                .enumCase(EnumCaseRef(typeName: tn, caseName: cn))
            }, setter: nil)
        }
    }

    // MARK: - Modifier Methods

    let modifierNames = [
        // Layout
        "padding", "frame", "fixedSize", "offset", "ignoresSafeArea", "zIndex",
        // Typography
        "font", "bold", "italic", "underline", "strikethrough", "lineLimit",
        "multilineTextAlignment",
        // Appearance
        "foregroundColor", "foregroundStyle", "background", "overlay",
        "opacity", "cornerRadius", "shadow", "border", "hidden", "blur",
        "clipShape", "mask", "tint", "accentColor",
        // Transforms
        "rotationEffect", "scaleEffect",
        // Interaction
        "disabled", "allowsHitTesting", "contentShape",
        // Navigation
        "navigationTitle",
        // Styling
        "listStyle",
        // Animation
        "animation", "transition", "contentTransition", "symbolEffect",
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
        guard let vm, let (ref, box) = unboxView(receiver), let closure = args.first else { return receiver }
        let action = makeContextAction(vm: vm, closure: closure)
        return boxView(AnyView(box.view.onAppear(perform: action)), typeName: ref.typeName)
    }

    registry.registerMethod(typeName: "View", selector: "onDisappear", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let (ref, box) = unboxView(receiver), let closure = args.first else { return receiver }
        let action = makeContextAction(vm: vm, closure: closure)
        return boxView(AnyView(box.view.onDisappear(perform: action)), typeName: ref.typeName)
    }

    registry.registerMethod(typeName: "View", selector: "onTapGesture", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let (ref, box) = unboxView(receiver), let closure = args.first else { return receiver }
        let action = makeContextAction(vm: vm, closure: closure)
        return boxView(AnyView(box.view.onTapGesture(perform: action)), typeName: ref.typeName)
    }

    // .onChange(of: value) { closure } — simplified: takes closure only
    registry.registerMethod(typeName: "View", selector: "onChange", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let (ref, box) = unboxView(receiver) else { return receiver }
        let closure = args.first(where: { if case .closure = $0 { return true }; return false })
        guard let closure else { return receiver }
        let action = makeContextAction(vm: vm, closure: closure)
        return boxView(AnyView(box.view.onAppear(perform: action)), typeName: ref.typeName)
    }

    // .task { async work } — runs closure on appear (simplified: same as onAppear)
    registry.registerMethod(typeName: "View", selector: "task", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let (ref, box) = unboxView(receiver), let closure = args.first else { return receiver }
        let action = makeContextAction(vm: vm, closure: closure)
        nonisolated(unsafe) let a = action
        return boxView(AnyView(box.view.task { a() }), typeName: ref.typeName)
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

    // Picker(title, selection: $binding) { options }
    registry.registerType("Picker") { args in
        let title = args.first(where: { $0.stringValue != nil })?.stringValue ?? ""
        if let bindingRef = args.compactMap({ extractBindingRef($0) }).first {
            let binding = Binding<String>(
                get: { bindingRef.stateStore.get(bindingRef.key).stringValue ?? "" },
                set: { bindingRef.stateStore.set(bindingRef.key, .string($0)) }
            )
            return .hostObject(HostObjectRef(object: ViewBox(AnyView(
                Picker(title, selection: binding) { Text("Option").tag("option") }
            )), typeName: "Picker"))
        }
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(
            Picker(title, selection: .constant("")) { EmptyView() }
        )), typeName: "Picker"))
    }

    // DatePicker(title, selection: $binding)
    registry.registerType("DatePicker") { args in
        let title = args.first(where: { $0.stringValue != nil })?.stringValue ?? ""
        // DatePicker requires a Date binding — simplified for prototyping
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(
            DatePicker(title, selection: .constant(Foundation.Date()))
        )), typeName: "DatePicker"))
    }

    // Stepper(title, value: $binding, in: range)
    registry.registerType("Stepper") { args in
        let title = args.first(where: { $0.stringValue != nil })?.stringValue ?? ""
        if let bindingRef = args.compactMap({ extractBindingRef($0) }).first {
            let binding = Binding<Int>(
                get: { bindingRef.stateStore.get(bindingRef.key).intValue ?? 0 },
                set: { bindingRef.stateStore.set(bindingRef.key, .int($0)) }
            )
            return .hostObject(HostObjectRef(object: ViewBox(AnyView(
                Stepper(title, value: binding)
            )), typeName: "Stepper"))
        }
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(
            Stepper(title, value: .constant(0))
        )), typeName: "Stepper"))
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
    let containerTypes = ["VStack", "HStack", "ZStack", "ScrollView", "Group", "List",
                          "NavigationStack", "Form", "Section", "LazyVStack", "LazyHStack"]

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
            case "Form":
                containerView = AnyView(Form { childBox.view })
            case "Section":
                let header = spacing?.stringValue ?? "" // reuse spacing arg slot for header text
                if !header.isEmpty {
                    containerView = AnyView(Section(header: Text(header)) { childBox.view })
                } else {
                    containerView = AnyView(Section { childBox.view })
                }
            case "LazyVStack":
                containerView = AnyView(LazyVStack(spacing: spacingValue ?? 8) { childBox.view })
            case "LazyHStack":
                containerView = AnyView(LazyHStack(spacing: spacingValue ?? 8) { childBox.view })
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

        let action: () -> Void = actionClosure.map { makeContextAction(vm: vm, closure: $0) } ?? {}

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

// MARK: - Navigation Views

private func registerNavigationViews(on registry: BridgeRegistry, vm: VM) {
    // NavigationLink("Title") { destination }
    registry.registerType("NavigationLink") { [weak vm] args in
        guard let vm else { return .nil_ }
        var title: String? = nil
        var destinationClosure: Value? = nil

        for arg in args {
            switch arg {
            case .string(let s): title = s
            case .closure: destinationClosure = arg
            default: break
            }
        }

        let view: AnyView
        if let title, let destClosure = destinationClosure {
            view = AnyView(NavigationLink(title) {
                if let result = try? vm.invokeValue(destClosure, args: []),
                   case .hostObject(let ref) = result, let box = ref.object as? ViewBox {
                    box.view
                } else {
                    EmptyView()
                }
            })
        } else if let title {
            view = AnyView(NavigationLink(title, destination: { EmptyView() }))
        } else {
            view = AnyView(EmptyView())
        }
        return .hostObject(HostObjectRef(object: ViewBox(view), typeName: "NavigationLink"))
    }

    // TabView { tabs }
    registry.registerType("TabView") { [weak vm] args in
        guard let vm else { return .nil_ }
        let collector = ViewCollector()
        var closureArg: Value? = nil

        for arg in args {
            if case .closure = arg { closureArg = arg }
        }

        if let closure = closureArg {
            let savedContext = vm.swiftUIContext
            let stateStore = savedContext?.stateStore ?? DummyStateStore()
            vm.swiftUIContext = SwiftUIContext(stateStore: stateStore, viewCollector: collector)
            let result = try vm.invokeValue(closure, args: [])
            vm.swiftUIContext = savedContext
            if case .hostObject(let ref) = result, let box = ref.object as? ViewBox {
                collector.views.append(box.view)
            }
        }

        let combined = collector.buildCombinedView()
        let view = AnyView(TabView { combined })
        return .hostObject(HostObjectRef(object: ViewBox(view), typeName: "TabView"))
    }

    // .tabItem { Label(...) }
    registry.registerMethod(typeName: "View", selector: "tabItem", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox,
              let closure = args.first else { return receiver }
        let modified = AnyView(box.view.tabItem {
            if let result = try? vm.invokeValue(closure, args: []),
               case .hostObject(let labelRef) = result, let labelBox = labelRef.object as? ViewBox {
                labelBox.view
            } else {
                EmptyView()
            }
        })
        return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
    }
}

// MARK: - withAnimation

private func registerWithAnimation(on registry: BridgeRegistry, vm: VM) {
    // withAnimation(.spring()) { state changes }
    // Parses animation type from first non-closure argument
    let withAnimFn = NativeFunctionRef(name: "withAnimation", arity: -1) { [weak vm] args in
        guard let vm else { return .void }
        let closure = args.first(where: { if case .closure = $0 { return true }; return false })
        // Parse animation type from non-closure args
        let animArgs = args.filter { if case .closure = $0 { return false }; return true }
        let animation = ModifierApplicator.parseAnimation(from: animArgs)

        if let closure {
            // Check for a second closure (completion handler)
            let closures = args.filter { if case .closure = $0 { return true }; return false }
            let completionClosure = closures.count > 1 ? closures[1] : nil

            var result: Value = .void
            if let completionClosure {
                withAnimation(animation) {
                    result = (try? vm.invokeValue(closure, args: [])) ?? .void
                } completion: {
                    _ = try? vm.invokeValue(completionClosure, args: [])
                }
            } else {
                withAnimation(animation) {
                    result = (try? vm.invokeValue(closure, args: [])) ?? .void
                }
            }
            return result
        }
        return .void
    }
    vm.environment.setGlobal("withAnimation", value: .nativeFunction(withAnimFn))
}

// MARK: - Presentation Modifiers

private func registerPresentationModifiers(on registry: BridgeRegistry, vm: VM) {
    #if os(iOS)
    // .fullScreenCover(isPresented: $binding) { content }
    registry.registerMethod(typeName: "View", selector: "fullScreenCover", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox else { return receiver }
        let bindingRef = args.compactMap { extractBindingRef($0) }.first
        let contentClosure = args.first(where: { if case .closure = $0 { return true }; return false })
        if let bindingRef, let contentClosure {
            let binding = Binding<Bool>(
                get: { bindingRef.stateStore.get(bindingRef.key).boolValue ?? false },
                set: { bindingRef.stateStore.set(bindingRef.key, .bool($0)) }
            )
            let modified = AnyView(box.view.fullScreenCover(isPresented: binding) {
                if let result = try? vm.invokeValue(contentClosure, args: []),
                   case .hostObject(let r) = result, let b = r.object as? ViewBox { b.view }
                else { EmptyView() }
            })
            return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
        }
        return receiver
    }
    #endif

    // .confirmationDialog(title, isPresented: $binding) { actions }
    registry.registerMethod(typeName: "View", selector: "confirmationDialog", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox else { return receiver }
        let title = args.first(where: { $0.stringValue != nil })?.stringValue ?? ""
        let bindingRef = args.compactMap { extractBindingRef($0) }.first
        let actionClosure = args.first(where: { if case .closure = $0 { return true }; return false })
        if let bindingRef {
            let binding = Binding<Bool>(
                get: { bindingRef.stateStore.get(bindingRef.key).boolValue ?? false },
                set: { bindingRef.stateStore.set(bindingRef.key, .bool($0)) }
            )
            let modified = AnyView(box.view.confirmationDialog(title, isPresented: binding) {
                if let actionClosure, let result = try? vm.invokeValue(actionClosure, args: []),
                   case .hostObject(let r) = result, let b = r.object as? ViewBox { b.view }
                else { Button("OK") { bindingRef.stateStore.set(bindingRef.key, .bool(false)) } }
            })
            return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
        }
        return receiver
    }

    // .toolbar { content }
    registry.registerMethod(typeName: "View", selector: "toolbar", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox,
              let closure = args.first(where: { if case .closure = $0 { return true }; return false }) else { return receiver }
        let modified = AnyView(box.view.toolbar {
            if let result = try? vm.invokeValue(closure, args: []),
               case .hostObject(let r) = result, let b = r.object as? ViewBox {
                ToolbarItem { b.view }
            }
        })
        return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
    }

    // .searchable(text: $binding)
    registry.registerMethod(typeName: "View", selector: "searchable", parameterLabels: []) { receiver, args in
        guard let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox else { return receiver }
        if let bindingRef = args.compactMap({ extractBindingRef($0) }).first {
            let binding = Binding<String>(
                get: { bindingRef.stateStore.get(bindingRef.key).stringValue ?? "" },
                set: { bindingRef.stateStore.set(bindingRef.key, .string($0)) }
            )
            let modified = AnyView(box.view.searchable(text: binding))
            return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
        }
        return receiver
    }

    // .refreshable { action }
    registry.registerMethod(typeName: "View", selector: "refreshable", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox,
              let closure = args.first else { return receiver }
        let modified = AnyView(box.view.refreshable { _ = try? vm.invokeValue(closure, args: []) })
        return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
    }

    // .swipeActions { buttons }
    registry.registerMethod(typeName: "View", selector: "swipeActions", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox,
              let closure = args.first else { return receiver }
        let modified = AnyView(box.view.swipeActions {
            if let result = try? vm.invokeValue(closure, args: []),
               case .hostObject(let r) = result, let b = r.object as? ViewBox { b.view }
        })
        return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
    }

    // .contextMenu { content }
    registry.registerMethod(typeName: "View", selector: "contextMenu", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox,
              let closure = args.first else { return receiver }
        let modified = AnyView(box.view.contextMenu {
            if let result = try? vm.invokeValue(closure, args: []),
               case .hostObject(let r) = result, let b = r.object as? ViewBox { b.view }
        })
        return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
    }

    // .onSubmit { action }
    registry.registerMethod(typeName: "View", selector: "onSubmit", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox,
              let closure = args.first else { return receiver }
        let modified = AnyView(box.view.onSubmit { _ = try? vm.invokeValue(closure, args: []) })
        return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
    }

    // .onLongPressGesture { action }
    registry.registerMethod(typeName: "View", selector: "onLongPressGesture", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox,
              let closure = args.first else { return receiver }
        let modified = AnyView(box.view.onLongPressGesture { _ = try? vm.invokeValue(closure, args: []) })
        return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
    }

    #if os(iOS)
    // .popover(isPresented: $binding) { content }
    registry.registerMethod(typeName: "View", selector: "popover", parameterLabels: []) { [weak vm] receiver, args in
        guard let vm, let ref = receiver.hostObjectRef, let box = ref.object as? ViewBox else { return receiver }
        let bindingRef = args.compactMap { extractBindingRef($0) }.first
        let contentClosure = args.first(where: { if case .closure = $0 { return true }; return false })
        if let bindingRef, let contentClosure {
            let binding = Binding<Bool>(
                get: { bindingRef.stateStore.get(bindingRef.key).boolValue ?? false },
                set: { bindingRef.stateStore.set(bindingRef.key, .bool($0)) }
            )
            let modified = AnyView(box.view.popover(isPresented: binding) {
                if let result = try? vm.invokeValue(contentClosure, args: []),
                   case .hostObject(let r) = result, let b = r.object as? ViewBox { b.view }
                else { EmptyView() }
            })
            return .hostObject(HostObjectRef(object: ViewBox(modified), typeName: ref.typeName))
        }
        return receiver
    }
    #endif
}

// MARK: - Additional Views (Grid, Menu, GeometryReader)

private func registerAdditionalViews(on registry: BridgeRegistry, vm: VM) {
    // Menu("Title") { actions }
    registry.registerType("Menu") { [weak vm] args in
        guard let vm else { return .nil_ }
        let title = args.first(where: { $0.stringValue != nil })?.stringValue ?? "Menu"
        let closure = args.first(where: { if case .closure = $0 { return true }; return false })
        if let closure {
            let view = AnyView(Menu(title) {
                if let result = try? vm.invokeValue(closure, args: []),
                   case .hostObject(let r) = result, let b = r.object as? ViewBox { b.view }
            })
            return .hostObject(HostObjectRef(object: ViewBox(view), typeName: "Menu"))
        }
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(Menu(title) { })), typeName: "Menu"))
    }

    // Grid { GridRow { ... } }
    registry.registerType("Grid") { [weak vm] args in
        guard let vm else { return .nil_ }
        let collector = ViewCollector()
        if let closure = args.first(where: { if case .closure = $0 { return true }; return false }) {
            let savedContext = vm.swiftUIContext
            let stateStore = savedContext?.stateStore ?? DummyStateStore()
            vm.swiftUIContext = SwiftUIContext(stateStore: stateStore, viewCollector: collector)
            let result = try vm.invokeValue(closure, args: [])
            vm.swiftUIContext = savedContext
            if case .hostObject(let ref) = result, let box = ref.object as? ViewBox {
                collector.views.append(box.view)
            }
        }
        let content = collector.buildCombinedView()
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(Grid { content })), typeName: "Grid"))
    }

    // GridRow { cells }
    registry.registerType("GridRow") { [weak vm] args in
        guard let vm else { return .nil_ }
        let collector = ViewCollector()
        if let closure = args.first(where: { if case .closure = $0 { return true }; return false }) {
            let savedContext = vm.swiftUIContext
            let stateStore = savedContext?.stateStore ?? DummyStateStore()
            vm.swiftUIContext = SwiftUIContext(stateStore: stateStore, viewCollector: collector)
            let result = try vm.invokeValue(closure, args: [])
            vm.swiftUIContext = savedContext
            if case .hostObject(let ref) = result, let box = ref.object as? ViewBox {
                collector.views.append(box.view)
            }
        }
        let content = collector.buildCombinedView()
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(GridRow { content })), typeName: "GridRow"))
    }

    // GeometryReader { geometry in ... }
    registry.registerType("GeometryReader") { [weak vm] args in
        guard let vm else { return .nil_ }
        let closure = args.first(where: { if case .closure = $0 { return true }; return false })
        if let closure {
            let view = AnyView(GeometryReader { proxy in
                // Pass geometry size as a dictionary to the closure
                let size: Value = .dictionary([
                    "width": .double(Double(proxy.size.width)),
                    "height": .double(Double(proxy.size.height))
                ])
                if let result = try? vm.invokeValue(closure, args: [size]),
                   case .hostObject(let ref) = result, let box = ref.object as? ViewBox {
                    box.view
                }
            })
            return .hostObject(HostObjectRef(object: ViewBox(view), typeName: "GeometryReader"))
        }
        return .hostObject(HostObjectRef(object: ViewBox(AnyView(EmptyView())), typeName: "GeometryReader"))
    }
}

// MARK: - Helpers

/// Wrap an AnyView in a ViewBox → HostObjectRef → Value.
func boxView(_ view: AnyView, typeName: String) -> Value {
    .hostObject(HostObjectRef(object: ViewBox(view), typeName: typeName))
}

/// Extract a ViewBox from a Value, or nil if not a view.
func unboxView(_ value: Value) -> (ref: HostObjectRef, box: ViewBox)? {
    guard case .hostObject(let ref) = value, let box = ref.object as? ViewBox else { return nil }
    return (ref, box)
}

/// Create a closure that invokes a Lantern closure with the SwiftUI context restored.
/// Used by Button actions, onAppear, onTapGesture, etc.
func makeContextAction(vm: VM, closure: Value) -> () -> Void {
    let capturedContext = vm.swiftUIContext
    return {
        let prev = vm.swiftUIContext
        vm.swiftUIContext = capturedContext
        defer { vm.swiftUIContext = prev }
        _ = try? vm.invokeValue(closure, args: [])
    }
}

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
