import Testing
@testable import LanternVM
@testable import LanternBridge

@Suite("Bridge Registry")
struct BridgeRegistryTests {
    @Test func registerAndCallFunction() throws {
        let r = BridgeRegistry()
        r.registerFunction("double", parameterLabels: [nil]) { args in
            guard case .int(let v) = args[0] else { return .nil_ }; return .int(v * 2)
        }
        let fn = r.lookupFunction("double")!
        #expect(try fn([.int(21)]) == .int(42))
    }
    @Test func registerAndCallMethod() throws {
        let r = BridgeRegistry()
        r.registerMethod(typeName: "Foo", selector: "bar", parameterLabels: []) { _, _ in .string("ok") }
        let m = r.lookupMethod(typeName: "Foo", selector: "bar")!
        #expect(try m(.nil_, []) == .string("ok"))
    }
    @Test func queryMethods() {
        let r = BridgeRegistry()
        r.registerType("Thing") { _ in .nil_ }
        r.registerMethod(typeName: "Thing", selector: "doIt", parameterLabels: []) { _, _ in .nil_ }
        #expect(r.isTypeRegistered("Thing"))
        #expect(r.isMethodRegistered(typeName: "Thing", selector: "doIt"))
        #expect(r.registeredMethods(forType: "Thing") == ["doIt"])
    }
    @Test func unregisteredReturnsNil() {
        #expect(BridgeRegistry().lookupFunction("nope") == nil)
    }
}

@Suite("Bridge Convertible")
struct BridgeConvertibleTests {
    @Test func intRoundTrip() { #expect(Int.fromInterpreterValue(42.toInterpreterValue()) == 42) }
    @Test func doubleRoundTrip() { #expect(Double.fromInterpreterValue(3.14.toInterpreterValue()) == 3.14) }
    @Test func boolRoundTrip() { #expect(Bool.fromInterpreterValue(true.toInterpreterValue()) == true) }
    @Test func stringRoundTrip() { #expect(String.fromInterpreterValue("hi".toInterpreterValue()) == "hi") }
}

@Suite("String Bridge")
struct StringBridgeTests {
    @Test func uppercased() throws {
        let r = BridgeRegistry(); registerStringBridge(on: r)
        let m = r.lookupMethod(typeName: "String", selector: "uppercased")!
        #expect(try m(.string("hello"), []) == .string("HELLO"))
    }
    @Test func contains() throws {
        let r = BridgeRegistry(); registerStringBridge(on: r)
        let m = r.lookupMethod(typeName: "String", selector: "contains")!
        #expect(try m(.string("hello world"), [.string("world")]) == .bool(true))
    }
}
