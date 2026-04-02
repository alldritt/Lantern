// Lantern Conformance Test Fixtures — Structs
// Each test is run through both Lantern and the Swift compiler.
// Output must match exactly.

// TEST: struct_basic
// EXPECT: Alice
struct Person {
let name: String
let age: Int
}
let p = Person(name: "Alice", age: 30)
print(p.name)
// END

// TEST: struct_both_properties
// EXPECT: Alice is 30
struct Person2 {
let name: String
let age: Int
}
let p2 = Person2(name: "Alice", age: 30)
print("\(p2.name) is \(p2.age)")
// END

// TEST: struct_mutable_property
// EXPECT: 100
struct Counter {
var count: Int
}
var c = Counter(count: 0)
c.count = 100
print(c.count)
// END

// TEST: struct_value_semantics
// EXPECT: 1
// 0
struct Box {
var value: Int
}
var a = Box(value: 0)
var b = a
b.value = 1
print(b.value)
print(a.value)
// END

// TEST: struct_method
// EXPECT: Hello, I'm Alice
struct Greeter {
let name: String
func greet() -> String {
return "Hello, I'm \(name)"
}
}
let g = Greeter(name: "Alice")
print(g.greet())
// END

// TEST: struct_mutating_method
// EXPECT: 3
struct Tally {
var count: Int = 0
mutating func increment() {
count += 1
}
}
var t = Tally()
t.increment()
t.increment()
t.increment()
print(t.count)
// END

// TEST: struct_computed_property
// EXPECT: 50
struct Rectangle {
var width: Int
var height: Int
var area: Int {
return width * height
}
}
let rect = Rectangle(width: 10, height: 5)
print(rect.area)
// END

// TEST: struct_computed_property_getter_setter
// EXPECT: 100
struct Temperature {
var celsius: Double
var fahrenheit: Double {
get {
return celsius * 9.0 / 5.0 + 32.0
}
set {
celsius = (newValue - 32.0) * 5.0 / 9.0
}
}
}
var temp = Temperature(celsius: 0)
temp.fahrenheit = 212.0
print(Int(temp.celsius))
// END

// TEST: struct_custom_init
// EXPECT: (5, 5)
struct Point {
var x: Int
var y: Int
init(xy: Int) {
x = xy
y = xy
}
}
let p = Point(xy: 5)
print("(\(p.x), \(p.y))")
// END

// TEST: struct_static_property
// EXPECT: 0
struct Origin {
static let zero = Origin(x: 0, y: 0)
var x: Int
var y: Int
}
print(Origin.zero.x)
// END

// TEST: struct_static_method
// EXPECT: 100
struct MathHelper {
static func square(_ n: Int) -> Int {
return n * n
}
}
print(MathHelper.square(10))
// END

// TEST: struct_method_returns_new
// EXPECT: (3, 6)
struct Vec2 {
var x: Int
var y: Int
func scaled(by factor: Int) -> Vec2 {
return Vec2(x: x * factor, y: y * factor)
}
}
let v = Vec2(x: 1, y: 2).scaled(by: 3)
print("(\(v.x), \(v.y))")
// END

// TEST: struct_with_array_property
// EXPECT: 3
struct Bag {
var items: [String]
}
var bag = Bag(items: ["a", "b"])
bag.items.append("c")
print(bag.items.count)
// END

// TEST: struct_with_optional_property
// EXPECT: none
struct Config {
var label: String?
}
let cfg = Config(label: nil)
print(cfg.label ?? "none")
// END

// TEST: struct_nested_access
// EXPECT: 5
struct Inner {
var value: Int
}
struct Outer {
var inner: Inner
}
let o = Outer(inner: Inner(value: 5))
print(o.inner.value)
// END

// TEST: struct_mutating_complex
// EXPECT: [1, 2, 3]
struct Stack {
var items: [Int] = []
mutating func push(_ item: Int) {
items.append(item)
}
mutating func pop() -> Int? {
return items.isEmpty ? nil : items.removeLast()
}
}
var stack = Stack()
stack.push(1)
stack.push(2)
stack.push(3)
print(stack.items)
// END

// TEST: struct_description
// EXPECT: Point(3, 4)
struct DescPoint {
var x: Int
var y: Int
func description() -> String {
return "Point(\(x), \(y))"
}
}
print(DescPoint(x: 3, y: 4).description())
// END

// TEST: struct_default_values
// EXPECT: 0 unnamed
struct Entity {
var health: Int = 100
var name: String = "unnamed"
var score: Int = 0
}
let e = Entity()
print("\(e.score) \(e.name)")
// END

// TEST: struct_in_array
// EXPECT: Alice
// Bob
struct NameHolder {
let name: String
}
let people = [NameHolder(name: "Alice"), NameHolder(name: "Bob")]
for p in people {
print(p.name)
}
// END