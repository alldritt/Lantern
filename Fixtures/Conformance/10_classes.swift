// Lantern Conformance Test Fixtures — Classes
// Each test is run through both Lantern and the Swift compiler.
// Output must match exactly.

// TEST: class_basic
// EXPECT: Alice
class Person {
var name: String
init(name: String) {
self.name = name
}
}
let p = Person(name: "Alice")
print(p.name)
// END

// TEST: class_reference_semantics
// EXPECT: Bob
// Bob
class Ref {
var value: String
init(_ value: String) { self.value = value }
}
let a = Ref("Alice")
let b = a
b.value = "Bob"
print(a.value)
print(b.value)
// END

// TEST: class_method
// EXPECT: Hello from Alice
class Greeter {
var name: String
init(name: String) { self.name = name }
func greet() -> String {
return "Hello from \(name)"
}
}
print(Greeter(name: "Alice").greet())
// END

// TEST: class_property_mutation
// EXPECT: 10
class Box {
var value: Int
init(_ value: Int) { self.value = value }
}
let box = Box(0)
box.value = 10
print(box.value)
// END

// TEST: class_identity
// EXPECT: true
// false
class Obj {
init() {}
}
let x = Obj()
let y = x
let z = Obj()
print(x === y)
print(x === z)
// END

// TEST: class_with_method_mutation
// EXPECT: 3
class Counter {
var count = 0
func increment() {
count += 1
}
}
let c = Counter()
c.increment()
c.increment()
c.increment()
print(c.count)
// END

// TEST: class_computed_property
// EXPECT: 78.5
class Circle {
var radius: Double
init(radius: Double) { self.radius = radius }
var area: Double {
return 3.14 * radius * radius
}
}
print(Circle(radius: 5.0).area)
// END

// TEST: class_with_array
// EXPECT: 3
class Collection {
var items: [String] = []
func add(_ item: String) {
items.append(item)
}
}
let col = Collection()
col.add("a")
col.add("b")
col.add("c")
print(col.items.count)
// END

// TEST: class_shared_state
// EXPECT: 2
class SharedState {
var observers: [String] = []
func register(_ name: String) {
observers.append(name)
}
}
let state = SharedState()
func addObserver(_ s: SharedState, _ name: String) {
s.register(name)
}
addObserver(state, "A")
addObserver(state, "B")
print(state.observers.count)
// END

// TEST: class_static_method
// EXPECT: 42
class Factory {
static func create() -> Int {
return 42
}
}
print(Factory.create())
// END

// TEST: class_static_property
// EXPECT: 0
class Defaults {
static var count = 0
}
print(Defaults.count)
// END

// TEST: class_multiple_instances
// EXPECT: Alice
// Bob
class Named {
var name: String
init(_ name: String) { self.name = name }
}
let names = [Named("Alice"), Named("Bob")]
for n in names {
print(n.name)
}
// END