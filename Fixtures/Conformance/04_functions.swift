// Lantern Conformance Test Fixtures — Functions
// Each test is run through both Lantern and the Swift compiler.
// Output must match exactly.

// TEST: simple_function
// EXPECT: Hello
func sayHello() {
print("Hello")
}
sayHello()
// END

// TEST: function_with_return
// EXPECT: 42
func getAnswer() -> Int {
return 42
}
print(getAnswer())
// END

// TEST: function_with_parameter
// EXPECT: Hello Alice
func greet(name: String) {
print("Hello \(name)")
}
greet(name: "Alice")
// END

// TEST: function_multiple_parameters
// EXPECT: 7
func add(a: Int, b: Int) -> Int {
return a + b
}
print(add(a: 3, b: 4))
// END

// TEST: function_argument_labels
// EXPECT: 5
func move(from start: Int, to end: Int) -> Int {
return end - start
}
print(move(from: 3, to: 8))
// END

// TEST: function_no_label
// EXPECT: 10
func double(_ n: Int) -> Int {
return n * 2
}
print(double(5))
// END

// TEST: function_default_parameter
// EXPECT: Hello World
// Hello Alice
func hello(name: String = "World") {
print("Hello \(name)")
}
hello()
hello(name: "Alice")
// END

// TEST: function_returning_string
// EXPECT: Hello World
func makeGreeting(name: String) -> String {
return "Hello \(name)"
}
print(makeGreeting(name: "World"))
// END

// TEST: function_returning_bool
// EXPECT: true
func isEven(_ n: Int) -> Bool {
return n % 2 == 0
}
print(isEven(4))
// END

// TEST: function_calling_function
// EXPECT: 25
func square(_ n: Int) -> Int {
return n * n
}
func sumOfSquares(_ a: Int, _ b: Int) -> Int {
return square(a) + square(b)
}
print(sumOfSquares(3, 4))
// END

// TEST: nested_function_calls
// EXPECT: 8
func addOne(_ n: Int) -> Int {
return n + 1
}
print(addOne(addOne(addOne(5))))
// END

// TEST: recursion_factorial
// EXPECT: 120
func factorial(_ n: Int) -> Int {
if n <= 1 { return 1 }
return n * factorial(n - 1)
}
print(factorial(5))
// END

// TEST: recursion_fibonacci
// EXPECT: 55
func fibonacci(_ n: Int) -> Int {
if n <= 1 { return n }
return fibonacci(n - 1) + fibonacci(n - 2)
}
print(fibonacci(10))
// END

// TEST: mutual_recursion
// EXPECT: true
func isEvenRec(_ n: Int) -> Bool {
if n == 0 { return true }
return isOddRec(n - 1)
}
func isOddRec(_ n: Int) -> Bool {
if n == 0 { return false }
return isEvenRec(n - 1)
}
print(isEvenRec(4))
// END

// TEST: function_with_var_parameter
// EXPECT: 10
func sumTo(_ n: Int) -> Int {
var total = 0
for i in 1...n {
total += i
}
return total
}
print(sumTo(4))
// END

// TEST: function_multiple_returns
// EXPECT: positive
func classify(_ n: Int) -> String {
if n > 0 {
return "positive"
} else if n < 0 {
return "negative"
} else {
return "zero"
}
}
print(classify(5))
// END

// TEST: function_early_return
// EXPECT: found at 2
func findIndex(of target: Int, in items: [Int]) -> Int {
for i in 0..<items.count {
if items[i] == target {
return i
}
}
return -1
}
print("found at \(findIndex(of: 30, in: [10, 20, 30, 40]))")
// END

// TEST: function_modifying_external_var
// EXPECT: 3
var globalCounter = 0
func increment() {
globalCounter += 1
}
increment()
increment()
increment()
print(globalCounter)
// END

// TEST: function_as_value
// EXPECT: 9
func square2(_ n: Int) -> Int {
return n * n
}
let f = square2
print(f(3))
// END

// TEST: function_passed_as_argument
// EXPECT: 10
func apply(_ fn: (Int) -> Int, to value: Int) -> Int {
return fn(value)
}
func doubleIt(_ n: Int) -> Int {
return n * 2
}
print(apply(doubleIt, to: 5))
// END

// TEST: function_returned_from_function
// EXPECT: 15
func makeAdder(_ amount: Int) -> (Int) -> Int {
func adder(_ n: Int) -> Int {
return n + amount
}
return adder
}
let addTen = makeAdder(10)
print(addTen(5))
// END

// TEST: nested_function
// EXPECT: 120
func outerFactorial(_ n: Int) -> Int {
func helper(_ n: Int, _ acc: Int) -> Int {
if n <= 1 { return acc }
return helper(n - 1, acc * n)
}
return helper(n, 1)
}
print(outerFactorial(5))
// END

// TEST: void_function_implicit_return
// EXPECT: done
func doNothing() {
}
doNothing()
print("done")
// END

// TEST: function_with_loop_and_accumulator
// EXPECT: Hello, Hello, Hello
func repeatString(_ s: String, times: Int) -> String {
var result = ""
for i in 0..<times {
if i > 0 {
result += ", "
}
result += s
}
return result
}
print(repeatString("Hello", times: 3))
// END