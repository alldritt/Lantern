// Lantern Conformance Test Fixtures — Compile Error Detection
// Verify that Lantern rejects code that Swift rejects.
// Each test expects an error. Tests with ERROR@N verify the error is on line N.

// === Missing Delimiters ===

// TEST: missing_closing_brace_func
// EXPECT: ERROR
func foo() {
    let x = 1
// END

// TEST: missing_closing_brace_struct
// EXPECT: ERROR
struct Foo {
    var x = 1
// END

// TEST: missing_closing_brace_if
// EXPECT: ERROR
if true {
    print("hello")
// END

// TEST: missing_closing_paren
// EXPECT: ERROR
print("hello"
// END

// TEST: missing_closing_bracket
// EXPECT: ERROR
let arr = [1, 2, 3
// END

// === Invalid Expressions ===

// TEST: extraneous_closing_brace
// EXPECT: ERROR
let x = 1
}
// END

// TEST: double_operator
// EXPECT: ERROR
let x = 1 + + 2
// END

// TEST: incomplete_let
// EXPECT: ERROR
let = 5
// END

// TEST: missing_assignment_value
// EXPECT: ERROR
var x =
// END

// === Invalid Declarations ===

// TEST: struct_missing_name
// EXPECT: ERROR
struct { var x = 1 }
// END

// TEST: func_missing_name
// EXPECT: ERROR
func () { }
// END

// TEST: enum_missing_name
// EXPECT: ERROR
enum { case a }
// END

// === Immutability ===

// TEST: reassign_let_constant
// EXPECT: ERROR
let x = 10
x = 20
// END

// TEST: reassign_let_string
// EXPECT: ERROR
let name = "Alice"
name = "Bob"
// END

// === Type Errors (that Swift catches at compile time) ===

// TEST: undefined_variable_in_expression
// EXPECT: ERROR
let y = undeclaredVariable + 1
// END

// TEST: undefined_function_call
// EXPECT: ERROR
undefinedFunction()
// END

// === Mismatched Delimiters ===

// TEST: paren_bracket_mismatch
// EXPECT: ERROR
let arr = [1, 2, 3)
// END

// TEST: bracket_paren_mismatch
// EXPECT: ERROR
let x = (1 + 2]
// END
