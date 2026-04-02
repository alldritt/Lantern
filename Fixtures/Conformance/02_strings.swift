// Lantern Conformance Test Fixtures — Strings
// Each test is run through both Lantern and the Swift compiler.
// Output must match exactly.

// TEST: string_literal
// EXPECT: Hello
print("Hello")
// END

// TEST: empty_string
// EXPECT:
print("")
// END

// TEST: string_concatenation
// EXPECT: Hello World
print("Hello" + " " + "World")
// END

// TEST: string_compound_assignment
// EXPECT: Hello World
var s = "Hello"
s += " World"
print(s)
// END

// TEST: string_interpolation_variable
// EXPECT: Hello World
let name = "World"
print("Hello \(name)")
// END

// TEST: string_interpolation_expression
// EXPECT: 2 + 3 = 5
print("2 + 3 = \(2 + 3)")
// END

// TEST: string_interpolation_multiple
// EXPECT: Alice is 30 years old
let who = "Alice"
let age = 30
print("\(who) is \(age) years old")
// END

// TEST: string_interpolation_nested
// EXPECT: Result: 42
let value = 42
print("Result: \(value)")
// END

// TEST: string_interpolation_in_variable
// EXPECT: Count: 5
let count = 5
let msg = "Count: \(count)"
print(msg)
// END

// TEST: string_count
// EXPECT: 5
let word = "Hello"
print(word.count)
// END

// TEST: string_isEmpty_false
// EXPECT: false
print("Hello".isEmpty)
// END

// TEST: string_isEmpty_true
// EXPECT: true
print("".isEmpty)
// END

// TEST: string_uppercased
// EXPECT: HELLO
print("Hello".uppercased())
// END

// TEST: string_lowercased
// EXPECT: hello
print("Hello".lowercased())
// END

// TEST: string_contains_true
// EXPECT: true
print("Hello World".contains("World"))
// END

// TEST: string_contains_false
// EXPECT: false
print("Hello World".contains("Goodbye"))
// END

// TEST: string_hasPrefix_true
// EXPECT: true
print("Hello World".hasPrefix("Hello"))
// END

// TEST: string_hasPrefix_false
// EXPECT: false
print("Hello World".hasPrefix("World"))
// END

// TEST: string_hasSuffix_true
// EXPECT: true
print("Hello World".hasSuffix("World"))
// END

// TEST: string_hasSuffix_false
// EXPECT: false
print("Hello World".hasSuffix("Hello"))
// END

// TEST: string_replacingOccurrences
// EXPECT: Hi World
import Foundation
print("Hello World".replacingOccurrences(of: "Hello", with: "Hi"))
// END

// TEST: multiline_string_concatenation
// EXPECT: abcdef
var result = ""
result += "abc"
result += "def"
print(result)
// END

// TEST: string_equality
// EXPECT: true
print("abc" == "abc")
// END

// TEST: string_inequality
// EXPECT: true
print("abc" != "def")
// END

// TEST: string_comparison_less_than
// EXPECT: true
print("abc" < "def")
// END

// TEST: string_comparison_greater_than
// EXPECT: true
print("def" > "abc")
// END

// TEST: string_in_loop
// EXPECT: ***
var stars = ""
for _ in 0..<3 {
stars += "*"
}
print(stars)
// END

// TEST: string_interpolation_bool
// EXPECT: Value is true
let flag = true
print("Value is \(flag)")
// END

// TEST: string_interpolation_double
// EXPECT: Pi is approximately 3.14
let pi = 3.14
print("Pi is approximately \(pi)")
// END

// TEST: string_repeated_concatenation
// EXPECT: aaaa
var repeated = ""
for _ in 0..<4 {
repeated += "a"
}
print(repeated)
// END

// TEST: string_from_int_interpolation
// EXPECT: The answer is 42
let answer = 42
print("The answer is \(answer)")
// END

// TEST: escape_sequences
// EXPECT: Line1
// Line2
print("Line1\nLine2")
// END

// TEST: tab_escape
// EXPECT: A	B
print("A\tB")
// END