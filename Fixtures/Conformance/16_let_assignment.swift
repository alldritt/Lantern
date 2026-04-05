// Lantern Conformance Test Fixtures — Let Assignment
// Tests deferred initialization of let constants.
// Swift allows assigning to a let constant exactly once,
// including in separate branches of if/else.

// TEST: let_deferred_init_zero
// EXPECT: zero
func testing(_ p1: Int) -> String {
    let r: String
    if p1 == 0 {
        r = "zero"
    } else {
        r = "\(p1)"
    }
    return r
}
print(testing(0))
// END

// TEST: let_deferred_init_nonzero
// EXPECT: 22
func testing2(_ p1: Int) -> String {
    let r: String
    if p1 == 0 {
        r = "zero"
    } else {
        r = "\(p1)"
    }
    return r
}
print(testing2(22))
// END

// TEST: let_deferred_init_branches
// EXPECT: negative
func classify(_ n: Int) -> String {
    let label: String
    if n < 0 {
        label = "negative"
    } else if n == 0 {
        label = "zero"
    } else {
        label = "positive"
    }
    return label
}
print(classify(-5))
// END

// TEST: let_deferred_init_positive
// EXPECT: positive
func classify2(_ n: Int) -> String {
    let label: String
    if n < 0 {
        label = "negative"
    } else if n == 0 {
        label = "zero"
    } else {
        label = "positive"
    }
    return label
}
print(classify2(10))
// END

// TEST: let_deferred_init_top_level
// EXPECT: hello
let greeting: String
if true {
greeting = "hello"
} else {
greeting = "goodbye"
}
print(greeting)
// END

// TEST: let_deferred_init_top_level_else
// EXPECT: goodbye
let farewell: String
let shouldLeave = true
if !shouldLeave {
farewell = "stay"
} else {
farewell = "goodbye"
}
print(farewell)
// END

// TEST: let_deferred_init_top_level_multi_branch
// EXPECT: medium
let size: String
let val = 50
if val < 10 {
size = "small"
} else if val < 100 {
size = "medium"
} else {
size = "large"
}
print(size)
// END
