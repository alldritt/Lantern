// Lantern Conformance Test Fixtures — Enums
// Each test is run through both Lantern and the Swift compiler.
// Output must match exactly.

// TEST: enum_simple
// EXPECT: north
enum Direction {
case north, south, east, west
}
let d = Direction.north
switch d {
case .north: print("north")
case .south: print("south")
case .east: print("east")
case .west: print("west")
}
// END

// TEST: enum_switch_exhaustive
// EXPECT: primary
enum Color {
case red, green, blue
}
let c = Color.red
switch c {
case .red: print("primary")
case .green: print("primary")
case .blue: print("primary")
}
// END

// TEST: enum_raw_value_int
// EXPECT: 2
enum Planet: Int {
case mercury = 1, venus, earth, mars
}
print(Planet.venus.rawValue)
// END

// TEST: enum_raw_value_string
// EXPECT: sm
enum Size: String {
case small = "sm"
case medium = "md"
case large = "lg"
}
print(Size.small.rawValue)
// END

// TEST: enum_associated_value
// EXPECT: width: 100 height: 50
enum Shape {
case circle(radius: Double)
case rectangle(width: Int, height: Int)
}
let s = Shape.rectangle(width: 100, height: 50)
switch s {
case .circle(let r):
print("radius: \(r)")
case .rectangle(let w, let h):
print("width: \(w) height: \(h)")
}
// END

// TEST: enum_associated_mixed
// EXPECT: loading
// loaded 42
// error: fail
enum State {
case loading
case loaded(Int)
case error(String)
}
func describe(_ state: State) {
switch state {
case .loading:
print("loading")
case .loaded(let value):
print("loaded \(value)")
case .error(let msg):
print("error: \(msg)")
}
}
describe(.loading)
describe(.loaded(42))
describe(.error("fail"))
// END

// TEST: enum_method
// EXPECT: true
enum Parity {
case even, odd
func isEven() -> Bool {
switch self {
case .even: return true
case .odd: return false
}
}
}
print(Parity.even.isEven())
// END

// TEST: enum_computed_property
// EXPECT: *
enum Priority {
case low, medium, high
var symbol: String {
switch self {
case .low: return "."
case .medium: return "-"
case .high: return "*"
}
}
}
print(Priority.high.symbol)
// END

// TEST: enum_in_array
// EXPECT: 3
enum Direction2 {
case north, south, east, west
}
let directions: [Direction2] = [.north, .south, .east]
print(directions.count)
// END

// TEST: enum_equality
// EXPECT: true
// false
enum Coin {
case heads, tails
}
print(Coin.heads == Coin.heads)
print(Coin.heads == Coin.tails)
// END

// TEST: enum_in_if
// EXPECT: go
enum Light {
case red, yellow, green
}
let light = Light.green
if light == .green {
print("go")
} else {
print("stop")
}
// END

// TEST: switch_with_where
// EXPECT: small positive
let value = 3
switch value {
case let x where x < 0:
print("negative")
case let x where x < 10:
print("small positive")
default:
print("large positive")
}
// END

// TEST: switch_multiple_values
// EXPECT: weekend
let day = "Saturday"
switch day {
case "Monday", "Tuesday", "Wednesday", "Thursday", "Friday":
print("weekday")
case "Saturday", "Sunday":
print("weekend")
default:
print("unknown")
}
// END

// TEST: switch_range
// EXPECT: teen
let age = 15
switch age {
case 0..<13:
print("child")
case 13..<20:
print("teen")
case 20..<65:
print("adult")
default:
print("senior")
}
// END

// TEST: enum_optional_pattern
// EXPECT: has value: 5
let opt: Int? = 5
switch opt {
case .some(let val):
print("has value: \(val)")
case .none:
print("nil")
}
// END

// TEST: enum_recursive_description
// EXPECT: (1 + (2 + 3))
indirect enum Expr {
case number(Int)
case add(Expr, Expr)
}
func describe(_ expr: Expr) -> String {
switch expr {
case .number(let n):
return "\(n)"
case .add(let left, let right):
return "(\(describe(left)) + \(describe(right)))"
}
}
let expr = Expr.add(.number(1), .add(.number(2), .number(3)))
print(describe(expr))
// END