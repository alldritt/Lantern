import Testing
import Foundation
@testable import Lantern

@Suite("Phase 6 — Types")
struct Phase6Tests {
    @Test func classWithCustomInit() {
        let src = """
        class Person {
            var name: String
            init(name: String) {
                self.name = name
            }
        }
        let p = Person(name: "Alice")
        print(p.name)
        """
        #expect(lanternOutput(src) == "Alice")
    }

    @Test func classReferenceSemantics() {
        let src = """
        class Ref {
            var value: String
            init(_ value: String) { self.value = value }
        }
        let a = Ref("Alice")
        let b = a
        b.value = "Bob"
        print(a.value)
        print(b.value)
        """
        #expect(lanternOutput(src) == "Bob\nBob")
    }

    @Test func classMethod() {
        let src = """
        class Greeter {
            var name: String
            init(name: String) { self.name = name }
            func greet() -> String {
                return "Hello from " + name
            }
        }
        print(Greeter(name: "Alice").greet())
        """
        #expect(lanternOutput(src) == "Hello from Alice")
    }

    @Test func structMethod() {
        let src = """
        struct Greeter {
            let name: String
            func greet() -> String {
                return "Hello from " + name
            }
        }
        let g = Greeter(name: "Alice")
        print(g.greet())
        """
        #expect(lanternOutput(src) == "Hello from Alice")
    }

    @Test func structMutableProperty() {
        let src = """
        struct Counter {
            var count: Int
        }
        var c = Counter(count: 0)
        c.count = 100
        print(c.count)
        """
        #expect(lanternOutput(src) == "100")
    }

    @Test func enumBasic() {
        let src = """
        enum Direction {
            case north, south, east, west
        }
        let d = Direction.north
        print(d)
        """
        // EnumCaseRef prints as "Direction.north"
        #expect(lanternOutput(src) == "Direction.north")
    }
}
