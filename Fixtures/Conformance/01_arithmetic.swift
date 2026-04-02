// Lantern Conformance Test Fixtures — Arithmetic
// Each test is run through both Lantern and the Swift compiler.
// Output must match exactly.

// TEST: add_integers
// EXPECT: 7
print(3 + 4)
// END

// TEST: add_doubles
// EXPECT: 5.5
print(2.5 + 3.0)
// END

// TEST: subtract_integers
// EXPECT: 6
print(10 - 4)
// END

// TEST: subtract_doubles
// EXPECT: 1.5
print(4.0 - 2.5)
// END

// TEST: multiply_integers
// EXPECT: 24
print(6 * 4)
// END

// TEST: multiply_doubles
// EXPECT: 7.5
print(2.5 * 3.0)
// END

// TEST: divide_integers
// EXPECT: 3
print(15 / 5)
// END

// TEST: integer_division_truncates
// EXPECT: 3
print(10 / 3)
// END

// TEST: divide_doubles
// EXPECT: 2.5
print(5.0 / 2.0)
// END

// TEST: modulo
// EXPECT: 1
print(10 % 3)
// END

// TEST: modulo_no_remainder
// EXPECT: 0
print(9 % 3)
// END

// TEST: negate_integer
// EXPECT: -5
print(-5)
// END

// TEST: negate_double
// EXPECT: -3.14
print(-3.14)
// END

// TEST: double_negation
// EXPECT: 5
let x = 5
print(-(-x))
// END

// TEST: precedence_multiply_before_add
// EXPECT: 14
print(2 + 3 * 4)
// END

// TEST: precedence_divide_before_subtract
// EXPECT: 8
print(10 - 4 / 2)
// END

// TEST: parentheses_override_precedence
// EXPECT: 20
print((2 + 3) * 4)
// END

// TEST: nested_parentheses
// EXPECT: 2
print((10 - (4 + 2)) / 2)
// END

// TEST: chained_addition
// EXPECT: 15
print(1 + 2 + 3 + 4 + 5)
// END

// TEST: chained_multiplication
// EXPECT: 120
print(1 * 2 * 3 * 4 * 5)
// END

// TEST: mixed_operations
// EXPECT: 13
print(3 + 4 * 2 + 2)
// END

// TEST: complex_expression
// EXPECT: 42
let a = 10
let b = 3
let c = 4
print(a * c + b - 1)
// END

// TEST: compound_assignment_add
// EXPECT: 15
var total = 10
total += 5
print(total)
// END

// TEST: compound_assignment_subtract
// EXPECT: 7
var n = 10
n -= 3
print(n)
// END

// TEST: compound_assignment_multiply
// EXPECT: 30
var m = 6
m *= 5
print(m)
// END

// TEST: compound_assignment_divide
// EXPECT: 4
var d = 20
d /= 5
print(d)
// END

// TEST: compound_assignment_modulo
// EXPECT: 1
var r = 10
r %= 3
print(r)
// END

// TEST: large_integer
// EXPECT: 1000000000
print(1000000 * 1000)
// END

// TEST: negative_arithmetic
// EXPECT: -3
print(-7 + 4)
// END

// TEST: negative_multiply
// EXPECT: -12
print(-3 * 4)
// END

// TEST: negative_multiply_negative
// EXPECT: 12
print(-3 * -4)
// END