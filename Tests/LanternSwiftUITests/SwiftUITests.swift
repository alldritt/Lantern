#if canImport(SwiftUI)
import Testing
@testable import LanternVM
@testable import LanternSwiftUI

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
