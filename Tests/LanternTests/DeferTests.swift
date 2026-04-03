import Testing
@testable import Lantern

@Suite("Defer")
struct DeferTests {
    @Test func singleDefer() {
        let src = """
        func f() {
            defer { print("deferred") }
            print("body")
        }
        f()
        """
        #expect(lanternOutput(src) == "body\ndeferred")
    }

    @Test func multipleDefers() {
        let src = """
        func f() {
            defer { print("second") }
            defer { print("third") }
            print("first")
        }
        f()
        """
        let result = lanternOutput(src)
        #expect(result == "first\nthird\nsecond", Comment(rawValue: "Got: [\(result)]"))
    }

    @Test func deferOnThrow() {
        let src = """
        enum E: Error { case boom }
        func f() throws {
            defer { print("cleanup") }
            print("start")
            throw E.boom
        }
        do { try f() } catch { print("caught") }
        """
        #expect(lanternOutput(src) == "start\ncleanup\ncaught")
    }
}
