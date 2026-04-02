// TEST: fold_int_add
// BEFORE: let x = 2 + 3
// AFTER:  let x = 5

// TEST: fold_int_mul
// BEFORE: let x = 4 * 5
// AFTER:  let x = 20

// TEST: fold_string_concat
// BEFORE: let x = "hello" + " world"
// AFTER:  let x = "hello world"

// TEST: fold_bool_not
// BEFORE: let x = !true
// AFTER:  let x = false

// TEST: fold_comparison
// BEFORE: let x = 3 < 5
// AFTER:  let x = true

// TEST: fold_nested
// BEFORE: let x = (2 + 3) * (4 + 1)
// AFTER:  let x = 25

// TEST: no_fold_variable
// BEFORE: let x = a + 3
// AFTER:  let x = a + 3
