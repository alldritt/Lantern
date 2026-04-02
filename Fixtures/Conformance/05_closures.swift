// Lantern Conformance Test Fixtures — Closures
// Each test is run through both Lantern and the Swift compiler.
// Output must match exactly.

// TEST: closure_basic
// EXPECT: 8
let double = { (n: Int) -> Int in
return n * 2
}
print(double(4))
// END

// TEST: closure_no_parameters
// EXPECT: Hello
let sayHi = { () -> String in
return "Hello"
}
print(sayHi())
// END

// TEST: closure_shorthand
// EXPECT: 9
let square = { (n: Int) in n * n }
print(square(3))
// END

// TEST: closure_captures_variable
// EXPECT: 15
let offset = 10
let addOffset = { (n: Int) -> Int in
return n + offset
}
print(addOffset(5))
// END

// TEST: closure_captures_multiple
// EXPECT: 23
let base = 20
let multiplier = 3
let compute = { (n: Int) -> Int in
return base + n * multiplier
}
print(compute(1))
// END

// TEST: closure_captures_var
// EXPECT: 3
var count = 0
let increment = {
count += 1
}
increment()
increment()
increment()
print(count)
// END

// TEST: closure_as_argument
// EXPECT: 4
// 16
// 36
func applyToEach(_ items: [Int], _ transform: (Int) -> Int) {
for item in items {
print(transform(item))
}
}
applyToEach([2, 4, 6]) { n in n * n }
// END

// TEST: trailing_closure
// EXPECT: 10
func perform(times: Int, action: () -> Void) {
for _ in 0..<times {
action()
}
}
var total = 0
perform(times: 5) {
total += 2
}
print(total)
// END

// TEST: closure_returned_from_function
// EXPECT: 30
func makeMultiplier(_ factor: Int) -> (Int) -> Int {
return { n in n * factor }
}
let triple = makeMultiplier(3)
print(triple(10))
// END

// TEST: closure_in_variable_reassigned
// EXPECT: 7
var operation: (Int, Int) -> Int = { a, b in a + b }
print(operation(3, 4))
// END

// TEST: closure_captures_loop_variable
// EXPECT: 0
// 1
// 2
var closures: [() -> Void] = []
for i in 0..<3 {
let captured = i
closures.append { print(captured) }
}
for c in closures {
c()
}
// END

// TEST: closure_modifies_captured_var
// EXPECT: 5
var accumulator = 0
let add = { (n: Int) in
accumulator += n
}
add(2)
add(3)
print(accumulator)
// END

// TEST: closure_nested
// EXPECT: 60
let outer = { (x: Int) -> (Int) -> Int in
return { y in x * y }
}
let inner = outer(6)
print(inner(10))
// END

// TEST: immediately_invoked_closure
// EXPECT: 42
let result = { () -> Int in
let a = 20
let b = 22
return a + b
}()
print(result)
// END

// TEST: closure_with_map_pattern
// EXPECT: 2
// 4
// 6
let numbers = [1, 2, 3]
let doubled = numbers.map { $0 * 2 }
for n in doubled {
print(n)
}
// END

// TEST: closure_with_filter_pattern
// EXPECT: 2
// 4
let items = [1, 2, 3, 4, 5]
let evens = items.filter { $0 % 2 == 0 }
for n in evens {
print(n)
}
// END

// TEST: closure_chained_map_filter
// EXPECT: 4
// 16
let values = [1, 2, 3, 4, 5]
let result2 = values.filter { $0 % 2 == 0 }.map { $0 * $0 }
for v in result2 {
print(v)
}
// END

// TEST: closure_forEach
// EXPECT: a
// b
// c
let letters = ["a", "b", "c"]
letters.forEach { letter in
print(letter)
}
// END

// TEST: closure_retains_value_after_scope
// EXPECT: 11
func makeCounter() -> () -> Int {
var n = 0
return {
n += 1
return n
}
}
let counter = makeCounter()
for _ in 0..<10 {
_ = counter()
}
print(counter())
// END

// TEST: two_closures_share_capture
// EXPECT: 3
// 3
func makePair() -> (() -> Void, () -> Int) {
var shared = 0
let inc = { shared += 1 }
let get = { shared }
return (inc, get)
}
let (inc, get) = makePair()
inc()
inc()
inc()
print(get())
print(get())
// END

// TEST: closure_with_default_capture
// EXPECT: 10
var x = 10
let capture = { [x] in
print(x)
}
x = 20
capture()
// END

// TEST: higher_order_compose
// EXPECT: 7
func compose(_ f: @escaping (Int) -> Int, _ g: @escaping (Int) -> Int) -> (Int) -> Int {
return { x in f(g(x)) }
}
let addOne = { (n: Int) in n + 1 }
let doubleIt = { (n: Int) in n * 2 }
let doubleThenAdd = compose(addOne, doubleIt)
print(doubleThenAdd(3))
// END