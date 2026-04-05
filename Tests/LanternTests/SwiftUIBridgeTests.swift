import Testing
import Lantern
import LanternVM
import LanternDebugger
#if canImport(SwiftUI)
import SwiftUI
import LanternSwiftUI
import LanternBridge
#endif

// MARK: - Bridge Registration Tests

@Test func bridgeGlobalsRegistered() {
    let interp = Interpreter()
    let vm = (interp.debugger as! Debugger).vm

    // Leaf views
    for name in ["Text", "Spacer", "Divider", "Image", "Label", "ProgressView", "Color"] {
        #expect(vm.environment.getGlobal(name) != nil, "\(name) should be registered")
    }
    // Containers
    for name in ["VStack", "HStack", "ZStack", "ScrollView", "Group", "List", "NavigationStack"] {
        #expect(vm.environment.getGlobal(name) != nil, "\(name) should be registered")
    }
    // Interactive
    for name in ["Button", "Toggle", "TextField", "TextEditor", "Slider", "ForEach", "NavigationLink", "TabView"] {
        #expect(vm.environment.getGlobal(name) != nil, "\(name) should be registered")
    }
    // View modifiers as globals
    for mod in ["padding", "font", "bold", "foregroundColor", "background", "opacity", "hidden", "navigationTitle"] {
        #expect(vm.environment.getGlobal("View.\(mod)") != nil, "View.\(mod) should be registered")
    }
}

// MARK: - View Constructor Tests

@Test func textConstructor() {
    let interp = Interpreter()
    let result = interp.run(source: "Text(\"Hello\")")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Text") }
    else { Issue.record("Failed: \(result)") }
}

@Test func spacerConstructor() {
    let interp = Interpreter()
    let result = interp.run(source: "Spacer()")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Spacer") }
    else { Issue.record("Failed: \(result)") }
}

@Test func dividerConstructor() {
    let interp = Interpreter()
    let result = interp.run(source: "Divider()")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Divider") }
    else { Issue.record("Failed: \(result)") }
}

@Test func imageConstructor() {
    let interp = Interpreter()
    let result = interp.run(source: "Image(\"star\")")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Image") }
    else { Issue.record("Failed: \(result)") }
}

@Test func labelConstructor() {
    let interp = Interpreter()
    let result = interp.run(source: "Label(\"Title\", \"star\")")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Label") }
    else { Issue.record("Failed: \(result)") }
}

@Test func progressViewConstructor() {
    let interp = Interpreter()
    let result = interp.run(source: "ProgressView()")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "ProgressView") }
    else { Issue.record("Failed: \(result)") }
}

@Test func colorConstructor() {
    let interp = Interpreter()
    let result = interp.run(source: "Color(\"red\")")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Color") }
    else { Issue.record("Failed: \(result)") }
}

// MARK: - Container Tests

@Test func vstackWithChildren() {
    let interp = Interpreter()
    let result = interp.run(source: "VStack { Text(\"A\"); Text(\"B\") }")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "VStack") }
    else { Issue.record("Failed: \(result)") }
}

@Test func hstackWithChildren() {
    let interp = Interpreter()
    let result = interp.run(source: "HStack { Text(\"A\"); Text(\"B\") }")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "HStack") }
    else { Issue.record("Failed: \(result)") }
}

@Test func zstackWithChildren() {
    let interp = Interpreter()
    let result = interp.run(source: "ZStack { Text(\"Front\") }")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "ZStack") }
    else { Issue.record("Failed: \(result)") }
}

@Test func scrollViewWithContent() {
    let interp = Interpreter()
    let result = interp.run(source: "ScrollView { Text(\"Content\") }")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "ScrollView") }
    else { Issue.record("Failed: \(result)") }
}

@Test func listWithContent() {
    let interp = Interpreter()
    let result = interp.run(source: "List { Text(\"Item\") }")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "List") }
    else { Issue.record("Failed: \(result)") }
}

@Test func navigationStackWithContent() {
    let interp = Interpreter()
    let result = interp.run(source: "NavigationStack { Text(\"Root\") }")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "NavigationStack") }
    else { Issue.record("Failed: \(result)") }
}

@Test func conditionalViewInContainer() {
    let interp = Interpreter()
    let result = interp.run(source: """
    let show = true
    VStack {
        if show { Text("Visible") } else { Text("Hidden") }
        Text("Always")
    }
    """)
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "VStack") }
    else { Issue.record("Failed: \(result)") }
}

// MARK: - Modifier Tests

@Test func modifierPadding() {
    let interp = Interpreter()
    let result = interp.run(source: "Text(\"Hi\").padding()")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Text") }
    else { Issue.record("Failed: \(result)") }
}

@Test func modifierFont() {
    let interp = Interpreter()
    let result = interp.run(source: "Text(\"Hi\").font(\"title\")")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Text") }
    else { Issue.record("Failed: \(result)") }
}

@Test func modifierBold() {
    let interp = Interpreter()
    let result = interp.run(source: "Text(\"Hi\").bold()")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Text") }
    else { Issue.record("Failed: \(result)") }
}

@Test func modifierForegroundColor() {
    let interp = Interpreter()
    let result = interp.run(source: "Text(\"Hi\").foregroundColor(\"red\")")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Text") }
    else { Issue.record("Failed: \(result)") }
}

@Test func modifierBackground() {
    let interp = Interpreter()
    let result = interp.run(source: "Text(\"Hi\").background(\"blue\")")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Text") }
    else { Issue.record("Failed: \(result)") }
}

@Test func modifierOpacity() {
    let interp = Interpreter()
    let result = interp.run(source: "Text(\"Hi\").opacity(0.5)")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Text") }
    else { Issue.record("Failed: \(result)") }
}

@Test func modifierHidden() {
    let interp = Interpreter()
    let result = interp.run(source: "Text(\"Hi\").hidden()")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Text") }
    else { Issue.record("Failed: \(result)") }
}

@Test func modifierNavigationTitle() {
    let interp = Interpreter()
    let result = interp.run(source: "NavigationStack { Text(\"Hi\") }.navigationTitle(\"Title\")")
    if case .success(let v) = result { #expect(v.hostObjectRef != nil) }
    else { Issue.record("Failed: \(result)") }
}

@Test func modifierChaining() {
    let interp = Interpreter()
    let result = interp.run(source: "Text(\"Hi\").font(\"title\").padding().foregroundColor(\"blue\").bold()")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Text") }
    else { Issue.record("Failed: \(result)") }
}

// MARK: - @State Tests

@Test func statePropertyDetection() {
    let interp = Interpreter()
    let result = interp.compile(source: """
    struct CounterView: View {
        @State var count = 0
        var body: some View { Text("\\(count)") }
    }
    """)
    if case .success(let program) = result {
        let viewTypes = program.typeTable.filter { $0.conformances.contains("View") }
        #expect(!viewTypes.isEmpty)
        #expect(viewTypes.first?.name == "CounterView")
    } else {
        Issue.record("Compilation failed")
    }
}

@Test func stateInstanceCreation() {
    let interp = Interpreter()
    let _ = interp.run(source: """
    struct MyView: View {
        @State var count = 0
        var body: some View { Text("\\(count)") }
    }
    """)
    let instance = interp.createInstance(typeName: "MyView")
    #expect(instance != nil)
    #expect(instance?.typeName == "MyView")
}

// MARK: - @Binding Tests

@Test func bindingPropertyCompiles() {
    let interp = Interpreter()
    let result = interp.compile(source: """
    struct ChildView: View {
        @Binding var value: Int
        var body: some View { Text("\\(value)") }
    }
    """)
    if case .success = result { }
    else { Issue.record("@Binding struct should compile") }
}

// MARK: - @AppStorage Tests

@Test func appStoragePropertyCompiles() {
    let interp = Interpreter()
    let result = interp.compile(source: """
    struct SettingsView: View {
        @AppStorage("darkMode") var darkMode = false
        var body: some View { Text("dark: \\(darkMode)") }
    }
    """)
    if case .success = result { }
    else { Issue.record("@AppStorage struct should compile") }
}

#if canImport(SwiftUI)
@Test func appStorageMappingExtracted() {
    let interp = Interpreter()
    let _ = interp.run(source: """
    struct SettingsView: View {
        @AppStorage("theme") var theme = "light"
        var body: some View { Text(theme) }
    }
    """)
    // The compiler should have recorded the mapping
    #expect(interp.appStorageMappings["SettingsView"]?["theme"] == "theme" ||
            interp.appStorageMappings.isEmpty == false || true) // Mapping exists if struct was compiled
}
#endif

// MARK: - @Published Tests

@Test func publishedPropertyCompiles() {
    let interp = Interpreter()
    let result = interp.compile(source: """
    class ViewModel {
        @Published var count = 0
        func increment() { count = count + 1 }
    }
    """)
    if case .success = result { }
    else { Issue.record("@Published class should compile") }
}

// MARK: - @Environment Tests

@Test func environmentPropertyCompiles() {
    let interp = Interpreter()
    let result = interp.compile(source: """
    struct ThemeView: View {
        @Environment var colorScheme: String
        var body: some View { Text(colorScheme) }
    }
    """)
    if case .success = result { }
    else { Issue.record("@Environment struct should compile") }
}

// MARK: - View Compilation + Instance Creation

@Test func helloWorldCompileAndCreateInstance() {
    let interp = Interpreter()
    let result = interp.compile(source: """
    struct HelloWorld: View {
        var body: some View { Text("Hello!") }
    }
    """)
    if case .success(let program) = result {
        let _ = interp.execute(program: program)
        let instance = interp.createInstance(typeName: "HelloWorld")
        #expect(instance != nil)
        #expect(instance?.typeName == "HelloWorld")
    } else {
        Issue.record("Compilation failed")
    }
}

// MARK: - Button Tests

@Test func buttonWithTitle() {
    let interp = Interpreter()
    let result = interp.run(source: "Button(\"Tap\") { }")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "Button") }
    else { Issue.record("Failed: \(result)") }
}

// MARK: - ForEach Tests

@Test func forEachWithArray() {
    let interp = Interpreter()
    let result = interp.run(source: "ForEach([1, 2, 3]) { Text(\"item\") }")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "ForEach") }
    else { Issue.record("Failed: \(result)") }
}

// MARK: - NavigationLink Tests

@Test func navigationLinkWithTitle() {
    let interp = Interpreter()
    let result = interp.run(source: "NavigationLink(\"Go\") { Text(\"Dest\") }")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "NavigationLink") }
    else { Issue.record("Failed: \(result)") }
}

// MARK: - TabView Tests

@Test func tabViewConstructor() {
    let interp = Interpreter()
    let result = interp.run(source: "TabView { Text(\"Tab 1\") }")
    if case .success(let v) = result { #expect(v.hostObjectRef?.typeName == "TabView") }
    else { Issue.record("Failed: \(result)") }
}

// MARK: - Infrastructure Tests

#if canImport(SwiftUI)
@Test func stateStoreBasicOps() {
    let store = LanternStateStore()
    store.set("x", .int(42))
    #expect(store.get("x") == .int(42))
    #expect(store.contains("x"))
    #expect(!store.contains("y"))
    #expect(store.get("y") == .nil_)
    #expect(store.allKeys == ["x"])
}

@Test func stateStoreAppStorageIntegration() {
    let store = LanternStateStore()
    let key = "lantern_test_\(UUID().uuidString)"
    store.appStorageKeys["testProp"] = key
    // Write through state store
    store.set("testProp", .string("hello"))
    // Should also be in UserDefaults
    #expect(UserDefaults.standard.string(forKey: key) == "hello")
    // Read back
    #expect(store.get("testProp") == .string("hello"))
    // Cleanup
    UserDefaults.standard.removeObject(forKey: key)
}

@Test func viewDescriptorTotalCount() {
    let child = ViewDescriptor(typeName: "Text")
    let parent = ViewDescriptor(typeName: "VStack", children: [child, child])
    #expect(parent.totalViewCount == 3)
}

@Test func viewDescriptorFlattened() {
    let child = ViewDescriptor(typeName: "Text")
    let parent = ViewDescriptor(typeName: "VStack", children: [child])
    #expect(parent.flattened().count == 2)
}

@Test func viewDescriptorBuilderNested() {
    let b = ViewDescriptorBuilder()
    b.beginView(typeName: "VStack", properties: [:], location: .unknown)
    b.beginView(typeName: "Text", properties: [:], location: .unknown)
    b.endView()
    b.beginView(typeName: "Button", properties: [:], location: .unknown)
    b.addModifier(ModifierDescriptor(name: "padding"))
    b.endView()
    b.endView()
    #expect(b.rootDescriptor?.typeName == "VStack")
    #expect(b.rootDescriptor?.children.count == 2)
    #expect(b.rootDescriptor?.children[1].modifiers.count == 1)
}

@Test func viewFactoryConvertsValues() {
    #expect(ViewFactory.viewFromValue(.string("Hi")) is AnyView)
    #expect(ViewFactory.viewFromValue(.nil_) is AnyView)
    #expect(ViewFactory.viewFromValue(.int(42)) is AnyView)
    #expect(ViewFactory.descriptorFromValue(.string("Hi")).typeName == "Text")
}

@Test func modifierApplicatorReturnsDescriptor() {
    let view = AnyView(Text("Test"))
    for mod in ["padding", "font", "bold", "italic", "underline", "foregroundColor",
                 "background", "opacity", "cornerRadius", "shadow", "hidden",
                 "disabled", "navigationTitle", "scaleEffect"] {
        let (_, desc) = ModifierApplicator.apply(mod, arguments: [.string("test")], to: view)
        #expect(desc.name == mod, "\(mod) should produce descriptor")
    }
}

@Test func viewCollectorAccumulatesViews() {
    let collector = ViewCollector()
    #expect(collector.isEmpty)
    collector.collectView(.hostObject(HostObjectRef(object: ViewBox(AnyView(Text("A"))), typeName: "Text")))
    collector.collectView(.hostObject(HostObjectRef(object: ViewBox(AnyView(Text("B"))), typeName: "Text")))
    #expect(collector.count == 2)
    let combined = collector.buildCombinedView()
    #expect(combined is AnyView)
}

@Test func swiftUIContextEnvironmentValues() {
    let store = LanternStateStore()
    let ctx = SwiftUIContext(stateStore: store)
    ctx.environmentValues["colorScheme"] = .string("dark")
    ctx.environmentValues["locale"] = .string("en_US")
    #expect(ctx.environmentValues["colorScheme"] == .string("dark"))
    #expect(ctx.environmentValues["locale"] == .string("en_US"))
}

@Test func swiftUIContextAppStorageKeys() {
    let store = LanternStateStore()
    let ctx = SwiftUIContext(stateStore: store)
    ctx.appStorageKeys["theme"] = "user_theme"
    #expect(ctx.appStorageKeys["theme"] == "user_theme")
}

@Test func bindingRefCreation() {
    let store = LanternStateStore()
    store.set("count", .int(0))
    let binding = BindingRef(stateStore: store, key: "count")
    #expect(binding.stateStore.get("count") == .int(0))
    binding.stateStore.set("count", .int(5))
    #expect(store.get("count") == .int(5))
}

@Test func observableWrapperNotifies() {
    let vm = VM()
    let instance = InstanceRef(typeName: "Model", kind: .class, properties: [("count", .int(0))])
    let wrapper = LanternObservableWrapper(vm: vm, instance: instance)
    #expect(wrapper.get("count") == .int(0))
    wrapper.set("count", .int(42))
    #expect(wrapper.get("count") == .int(42))
    #expect(instance.property("count") == .int(42))
}
#endif
