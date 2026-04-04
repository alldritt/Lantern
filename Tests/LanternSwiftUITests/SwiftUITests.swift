#if canImport(SwiftUI)
import Testing
import SwiftUI
@testable import LanternVM
@testable import LanternSwiftUI
@testable import LanternBridge

@Suite("LanternStateStore")
struct StateStoreTests {
    @Test func setGet() {
        let s = LanternStateStore(); s.set("count", .int(42))
        #expect(s.get("count") == .int(42))
    }
    @Test func defaultNil() { #expect(LanternStateStore().get("x") == .nil_) }
    @Test func contains() {
        let s = LanternStateStore(); #expect(!s.contains("x"))
        s.set("x", .int(1)); #expect(s.contains("x"))
    }
    @Test func allKeys() {
        let s = LanternStateStore(); s.set("a", .int(1)); s.set("b", .int(2))
        #expect(s.allKeys.sorted() == ["a", "b"])
    }
}

@Suite("ViewDescriptor")
struct ViewDescriptorTests {
    @Test func totalCount() {
        let child = ViewDescriptor(typeName: "Text")
        let parent = ViewDescriptor(typeName: "VStack", children: [child, child])
        #expect(parent.totalViewCount == 3)
    }
    @Test func flattened() {
        let child = ViewDescriptor(typeName: "Text")
        let parent = ViewDescriptor(typeName: "VStack", children: [child])
        #expect(parent.flattened().count == 2)
    }
    @Test func findByLocation() {
        let loc = SourceLocation(line: 5, column: 1)
        let child = ViewDescriptor(typeName: "Text", sourceLocation: loc)
        let parent = ViewDescriptor(typeName: "VStack", children: [child])
        #expect(parent.descriptor(at: loc)?.typeName == "Text")
    }
}

@Suite("SwiftUIContext")
struct SwiftUIContextTests {
    @Test func stateOpcodes() {
        let store = LanternStateStore()
        let ctx = SwiftUIContext(stateStore: store)
        let vm = VM()
        vm.swiftUIContext = ctx

        // State store protocol conformance
        store.set("count", .int(0))
        #expect(store.get("count") == .int(0))
        store.set("count", .int(42))
        #expect(store.get("count") == .int(42))
        #expect(store.contains("count"))
        #expect(!store.contains("missing"))
    }

    @Test func viewFactoryConvertsValues() {
        // String → Text view
        let textView = ViewFactory.viewFromValue(.string("Hello"))
        #expect(textView is AnyView)

        // Nil → EmptyView
        let emptyView = ViewFactory.viewFromValue(.nil_)
        #expect(emptyView is AnyView)

        // Descriptor from string value
        let desc = ViewFactory.descriptorFromValue(.string("Hello"))
        #expect(desc.typeName == "Text")
    }

    @Test func modifierApplicator() {
        let textView = AnyView(Text("Hello"))
        let (_, descriptor) = ModifierApplicator.apply("padding", arguments: [], to: textView)
        #expect(descriptor.name == "padding")
    }

    @Test func bridgeRegistersViewTypes() {
        let registry = BridgeRegistry()
        registerSwiftUIBridge(on: registry)
        #expect(registry.isTypeRegistered("Text"))
        #expect(registry.isTypeRegistered("Spacer"))
        #expect(registry.isTypeRegistered("Divider"))
        #expect(registry.isTypeRegistered("Image"))
        #expect(registry.isTypeRegistered("Color"))
        #expect(registry.isTypeRegistered("ProgressView"))
    }

    @Test func bridgeRegistersContainersWithVM() {
        let registry = BridgeRegistry()
        let vm = VM()
        registerSwiftUIBridge(on: registry, vm: vm)
        #expect(registry.isTypeRegistered("VStack"))
        #expect(registry.isTypeRegistered("HStack"))
        #expect(registry.isTypeRegistered("Button"))
        #expect(registry.isTypeRegistered("NavigationStack"))
    }

    @Test func bridgeTextConstructor() throws {
        let registry = BridgeRegistry()
        registerSwiftUIBridge(on: registry)
        guard let constructor = registry.lookupConstructor("Text") else {
            Issue.record("Text constructor not found"); return
        }
        let result = try constructor([.string("Hello")])
        if case .hostObject(let ref) = result {
            #expect(ref.typeName == "Text")
            #expect(ref.object is ViewBox)
        } else {
            Issue.record("Expected hostObject")
        }
    }
}

@Suite("ViewDescriptorBuilder")
struct ViewDescriptorBuilderTests {
    @Test func buildSimple() {
        let b = ViewDescriptorBuilder()
        b.beginView(typeName: "Text", properties: ["text": .string("Hi")], location: .unknown)
        b.endView()
        #expect(b.rootDescriptor?.typeName == "Text")
    }
    @Test func buildNested() {
        let b = ViewDescriptorBuilder()
        b.beginView(typeName: "VStack", properties: [:], location: .unknown)
        b.beginView(typeName: "Text", properties: [:], location: .unknown)
        b.endView()
        b.endView()
        #expect(b.rootDescriptor?.typeName == "VStack")
        #expect(b.rootDescriptor?.children.count == 1)
    }
    @Test func addModifier() {
        let b = ViewDescriptorBuilder()
        b.beginView(typeName: "Text", properties: [:], location: .unknown)
        b.addModifier(ModifierDescriptor(name: "padding"))
        b.endView()
        #expect(b.rootDescriptor?.modifiers.count == 1)
        #expect(b.rootDescriptor?.modifiers.first?.name == "padding")
    }
}
#endif
