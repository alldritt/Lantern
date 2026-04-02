import Testing
@testable import LanternVM

@Suite("Value")
struct ValueTests {
    @Test func intEquality() { #expect(Value.int(42) == .int(42)); #expect(Value.int(1) != .int(2)) }
    @Test func doubleEquality() { #expect(Value.double(3.14) == .double(3.14)) }
    @Test func boolEquality() { #expect(Value.bool(true) != .bool(false)) }
    @Test func stringEquality() { #expect(Value.string("hi") == .string("hi")) }
    @Test func nilEquality() { #expect(Value.nil_ == .nil_); #expect(Value.nil_ != .int(0)) }
    @Test func voidEquality() { #expect(Value.void == .void) }
    @Test func arrayEquality() { #expect(Value.array([.int(1)]) == .array([.int(1)])) }

    @Test func truthiness() {
        #expect(Value.bool(true).isTruthy); #expect(!Value.bool(false).isTruthy)
        #expect(!Value.nil_.isTruthy); #expect(Value.int(1).isTruthy)
        #expect(!Value.int(0).isTruthy); #expect(!Value.void.isTruthy)
    }

    @Test func isNil() {
        #expect(Value.nil_.isNil); #expect(Value.optional(nil).isNil)
        #expect(!Value.int(0).isNil); #expect(!Value.optional(.int(1)).isNil)
    }

    @Test func convenienceAccessors() {
        #expect(Value.int(42).intValue == 42); #expect(Value.string("x").intValue == nil)
        #expect(Value.double(3.14).doubleValue == 3.14); #expect(Value.int(5).doubleValue == 5.0)
        #expect(Value.bool(true).boolValue == true); #expect(Value.string("x").stringValue == "x")
        #expect(Value.array([.int(1)]).arrayValue?.count == 1)
        #expect(Value.dictionary(["a": .int(1)]).dictionaryValue?["a"] == .int(1))
    }

    @Test func description() {
        #expect(Value.int(42).description == "42")
        #expect(Value.string("hello").description == "hello")
        #expect(Value.bool(true).description == "true")
        #expect(Value.nil_.description == "nil")
        #expect(Value.void.description == "()")
    }

    @Test func debugSummary() {
        #expect(Value.array([.int(1), .int(2)]).debugSummary == "Array (2 elements)")
        #expect(Value.dictionary(["a": .int(1)]).debugSummary == "Dictionary (1 entries)")
        let long = Value.string(String(repeating: "x", count: 100))
        #expect(long.debugSummary.contains("100 characters"))
    }

    @Test func debugChildren() {
        let arr = Value.array([.int(1), .int(2)])
        #expect(arr.debugChildren?.count == 2)
        #expect(arr.debugChildren?[0].label == "[0]")
        #expect(Value.int(42).debugChildren == nil)
    }

    @Test func typeName() {
        #expect(Value.int(0).typeName == "Int")
        #expect(Value.double(0).typeName == "Double")
        #expect(Value.void.typeName == "Void")
        #expect(Value.range(0, 5, false).typeName == "Range")
    }
}
