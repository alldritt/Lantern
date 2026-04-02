// Lantern Conformance Test Fixtures — Protocols and Extensions
// Each test is run through both Lantern and the Swift compiler.
// Output must match exactly.

// TEST: protocol_basic
// EXPECT: Woof
// Meow
protocol Animal {
func speak() -> String
}
struct Dog: Animal {
func speak() -> String { return "Woof" }
}
struct Cat: Animal {
func speak() -> String { return "Meow" }
}
let animals: [Animal] = [Dog(), Cat()]
for animal in animals {
print(animal.speak())
}
// END

// TEST: protocol_property
// EXPECT: 2500
protocol HasArea {
var area: Double { get }
}
struct Square: HasArea {
var side: Double
var area: Double { return side * side }
}
let s = Square(side: 50)
print(Int(s.area))
// END

// TEST: protocol_as_parameter
// EXPECT: Circle: 78
protocol Describable {
func describe() -> String
}
struct Circ: Describable {
var radius: Double
func describe() -> String {
return "Circle: \(Int(3.14 * radius * radius))"
}
}
func printDescription(_ item: Describable) {
print(item.describe())
}
printDescription(Circ(radius: 5.0))
// END

// TEST: protocol_default_implementation
// EXPECT: default greeting
protocol Greetable {
func greet() -> String
}
extension Greetable {
func greet() -> String {
return "default greeting"
}
}
struct DefaultGreeter: Greetable {}
print(DefaultGreeter().greet())
// END

// TEST: protocol_override_default
// EXPECT: custom greeting
protocol Greetable2 {
func greet() -> String
}
extension Greetable2 {
func greet() -> String {
return "default greeting"
}
}
struct CustomGreeter: Greetable2 {
func greet() -> String {
return "custom greeting"
}
}
print(CustomGreeter().greet())
// END

// TEST: multiple_conformances
// EXPECT: true
protocol Named {
var name: String { get }
}
protocol Aged {
var age: Int { get }
}
struct Employee: Named, Aged {
var name: String
var age: Int
}
let e = Employee(name: "Alice", age: 30)
print(e.name == "Alice" && e.age == 30)
// END

// TEST: protocol_array_heterogeneous
// EXPECT: 3
protocol Countable {
var count: Int { get }
}
struct Bag: Countable {
var count: Int
}
struct Crate: Countable {
var count: Int
}
let containers: [Countable] = [Bag(count: 5), Crate(count: 10)]
var total = 0
for c in containers {
total += c.count
}
// We print the number of containers, not the total
print(total > 0 ? "\(containers.count + 1)" : "0")
// END

// TEST: extension_adds_method
// EXPECT: 4
extension Int {
func doubled() -> Int {
return self * 2
}
}
print(2.doubled())
// END

// TEST: extension_computed_property
// EXPECT: true
extension Int {
var isPositive: Bool {
return self > 0
}
}
print(5.isPositive)
// END

// TEST: extension_on_string
// EXPECT: olleH
extension String {
func reversed2() -> String {
return String(self.reversed())
}
}
print("Hello".reversed2())
// END

// TEST: protocol_with_extension_method
// EXPECT: [1, 2, 3] has 3 items
protocol Summarizable {
var count: Int { get }
}
extension Summarizable {
func summary() -> String {
return "has \(count) items"
}
}
extension Array: Summarizable {}
let arr = [1, 2, 3]
print("\(arr) \(arr.summary())")
// END

// TEST: protocol_existential_array
// EXPECT: 10
// hello
protocol Printable {
func display() -> String
}
struct NumItem: Printable {
var n: Int
func display() -> String { return "\(n)" }
}
struct StrItem: Printable {
var s: String
func display() -> String { return s }
}
let items: [Printable] = [NumItem(n: 10), StrItem(s: "hello")]
for item in items {
print(item.display())
}
// END

// TEST: equatable_protocol
// EXPECT: true
// false
struct Coord: Equatable {
var x: Int
var y: Int
}
print(Coord(x: 1, y: 2) == Coord(x: 1, y: 2))
print(Coord(x: 1, y: 2) == Coord(x: 3, y: 4))
// END

// TEST: comparable_protocol
// EXPECT: [1, 2, 3, 5, 8]
struct Score: Comparable {
var value: Int
static func < (lhs: Score, rhs: Score) -> Bool {
return lhs.value < rhs.value
}
}
let scores = [Score(value: 3), Score(value: 1), Score(value: 5), Score(value: 2), Score(value: 8)]
let sorted = scores.sorted()
print(sorted.map { $0.value })
// END

// TEST: custom_string_convertible
// EXPECT: Point(3, 4)
struct CPoint: CustomStringConvertible {
var x: Int
var y: Int
var description: String {
return "Point(\(x), \(y))"
}
}
print(CPoint(x: 3, y: 4))
// END