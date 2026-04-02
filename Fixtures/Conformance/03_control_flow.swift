// Lantern Conformance Test Fixtures — Control Flow
// Each test is run through both Lantern and the Swift compiler.
// Output must match exactly.

// TEST: if_true
// EXPECT: yes
if true {
print("yes")
}
// END

// TEST: if_false
// EXPECT:
if false {
print("no")
}
// END

// TEST: if_else_true
// EXPECT: yes
if true {
print("yes")
} else {
print("no")
}
// END

// TEST: if_else_false
// EXPECT: no
if false {
print("yes")
} else {
print("no")
}
// END

// TEST: if_else_if
// EXPECT: two
let x = 2
if x == 1 {
print("one")
} else if x == 2 {
print("two")
} else {
print("other")
}
// END

// TEST: if_else_if_chain
// EXPECT: C
let score = 75
if score >= 90 {
print("A")
} else if score >= 80 {
print("B")
} else if score >= 70 {
print("C")
} else if score >= 60 {
print("D")
} else {
print("F")
}
// END

// TEST: nested_if
// EXPECT: both
let a = true
let b = true
if a {
if b {
print("both")
}
}
// END

// TEST: if_with_expression
// EXPECT: positive
let n = 5
if n > 0 {
print("positive")
} else if n < 0 {
print("negative")
} else {
print("zero")
}
// END

// TEST: if_compound_condition
// EXPECT: in range
let val = 15
if val >= 10 && val <= 20 {
print("in range")
} else {
print("out of range")
}
// END

// TEST: if_or_condition
// EXPECT: match
let c = 3
if c == 1 || c == 3 || c == 5 {
print("match")
} else {
print("no match")
}
// END

// TEST: while_loop_basic
// EXPECT: 0
// 1
// 2
var i = 0
while i < 3 {
print(i)
i += 1
}
// END

// TEST: while_loop_never_enters
// EXPECT: done
var j = 10
while j < 5 {
print(j)
j += 1
}
print("done")
// END

// TEST: while_loop_sum
// EXPECT: 55
var sum = 0
var counter = 1
while counter <= 10 {
sum += counter
counter += 1
}
print(sum)
// END

// TEST: while_loop_break
// EXPECT: 0
// 1
// 2
var k = 0
while k < 10 {
if k == 3 {
break
}
print(k)
k += 1
}
// END

// TEST: while_loop_continue
// EXPECT: 1
// 3
// 5
var m = 0
while m < 6 {
m += 1
if m % 2 == 0 {
continue
}
print(m)
}
// END

// TEST: for_in_range_exclusive
// EXPECT: 0
// 1
// 2
for i in 0..<3 {
print(i)
}
// END

// TEST: for_in_range_inclusive
// EXPECT: 1
// 2
// 3
for i in 1...3 {
print(i)
}
// END

// TEST: for_in_empty_range
// EXPECT: done
for _ in 0..<0 {
print("never")
}
print("done")
// END

// TEST: for_in_single
// EXPECT: 5
for i in 5...5 {
print(i)
}
// END

// TEST: for_in_sum
// EXPECT: 15
var total = 0
for i in 1...5 {
total += i
}
print(total)
// END

// TEST: for_in_break
// EXPECT: 0
// 1
// 2
for i in 0..<10 {
if i == 3 {
break
}
print(i)
}
// END

// TEST: for_in_continue
// EXPECT: 1
// 3
// 5
// 7
// 9
for i in 0..<10 {
if i % 2 == 0 {
continue
}
print(i)
}
// END

// TEST: nested_for_loops
// EXPECT: 0,0
// 0,1
// 1,0
// 1,1
for i in 0..<2 {
for j in 0..<2 {
print("\(i),\(j)")
}
}
// END

// TEST: nested_for_break_inner
// EXPECT: 0:0
// 1:0
// 2:0
for i in 0..<3 {
for j in 0..<3 {
if j == 1 {
break
}
print("\(i):\(j)")
}
}
// END

// TEST: for_in_with_computation
// EXPECT: 1
// 4
// 9
// 16
// 25
for i in 1...5 {
print(i * i)
}
// END

// TEST: fizzbuzz
// EXPECT: 1
// 2
// Fizz
// 4
// Buzz
// Fizz
// 7
// 8
// Fizz
// Buzz
// 11
// Fizz
// 13
// 14
// FizzBuzz
for i in 1...15 {
if i % 15 == 0 {
print("FizzBuzz")
} else if i % 3 == 0 {
print("Fizz")
} else if i % 5 == 0 {
print("Buzz")
} else {
print(i)
}
}
// END

// TEST: variable_shadowing_in_loop
// EXPECT: 0
// 1
// 2
// outer: 10
let outer = 10
for i in 0..<3 {
print(i)
}
print("outer: \(outer)")
// END

// TEST: while_with_complex_condition
// EXPECT: 32
var power = 1
while power < 20 {
power *= 2
}
print(power)
// END

// TEST: nested_while_and_for
// EXPECT: 6
var result = 0
var row = 0
while row < 3 {
for col in 0..<(row + 1) {
result += 1
}
row += 1
}
print(result)
// END

// TEST: boolean_not
// EXPECT: true
print(!false)
// END

// TEST: boolean_and
// EXPECT: false
print(true && false)
// END

// TEST: boolean_or
// EXPECT: true
print(true || false)
// END

// TEST: boolean_complex
// EXPECT: true
let p = true
let q = false
let r = true
print((p || q) && r)
// END

// TEST: comparison_equal
// EXPECT: true
print(5 == 5)
// END

// TEST: comparison_not_equal
// EXPECT: true
print(5 != 3)
// END

// TEST: comparison_less_than
// EXPECT: true
print(3 < 5)
// END

// TEST: comparison_greater_than
// EXPECT: true
print(5 > 3)
// END

// TEST: comparison_less_equal
// EXPECT: true
print(5 <= 5)
// END

// TEST: comparison_greater_equal
// EXPECT: true
print(5 >= 5)
// END

// TEST: short_circuit_and
// EXPECT: false
var sideEffect = false
func setFlag() -> Bool {
sideEffect = true
return true
}
if false && setFlag() {
print("never")
}
print(sideEffect)
// END

// TEST: short_circuit_or
// EXPECT: true
var called = false
func markCalled() -> Bool {
called = true
return false
}
if true || markCalled() {
// markCalled should not execute
}
print(!called)
// END