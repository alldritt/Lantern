// Lantern Conformance Test Fixtures — Negative Tests
// Tests that verify correct error reporting.
// Tests with EXPECT: ERROR pass if the interpreter produces any error
// (compile-time or runtime). They fail if execution succeeds silently.

// === COMPILE-TIME ERRORS ===

// TEST: assign_to_let
// EXPECT: ERROR
let immutable = 42
immutable = 99
// END

// TEST: assign_to_let_string
// EXPECT: ERROR
let name = "Alice"
name = "Bob"
// END

// TEST: undefined_variable
// EXPECT: ERROR
print(doesNotExist)
// END

// TEST: undefined_function
// EXPECT: ERROR
undefinedFunction()
// END

// === RUNTIME ERRORS ===

// TEST: divide_by_zero
// EXPECT: ERROR
let x = 10 / 0
// END

// TEST: force_unwrap_nil
// EXPECT: ERROR
let opt: Int? = nil
let val = opt!
// END

// TEST: array_index_out_of_bounds
// EXPECT: ERROR
let arr = [1, 2, 3]
let item = arr[10]
// END

// TEST: stack_overflow_recursion
// EXPECT: ERROR
func infinite() -> Int { return infinite() }
let _ = infinite()
// END

// TEST: wrong_argument_count
// EXPECT: ERROR
func takesTwo(_ a: Int, _ b: Int) -> Int { return a + b }
let _ = takesTwo(1)
// END

// === TYPE ERRORS ===

// TEST: add_string_and_int
// EXPECT: ERROR
let bad = "hello" + 42
// END

// TEST: subtract_strings
// EXPECT: ERROR
let bad2 = "hello" - "world"
// END

// TEST: negate_string
// EXPECT: ERROR
let bad3 = -"hello"
// END

// === ERROR HANDLING ERRORS ===

// TEST: uncaught_throw
// EXPECT: ERROR
enum MyError: Error { case failed }
throw MyError.failed
// END

// TEST: throw_outside_do
// EXPECT: ERROR
func mightFail() throws { throw MyError.failed }
enum MyError2: Error { case failed }
try mightFail()
// END
