// Lantern Conformance Test Fixtures — Core Type Methods
// Verify that built-in type methods match Swift behavior.

// === Int ===

// TEST: int_is_multiple_true
// EXPECT: true
print((9).isMultiple(of: 3))
// END

// TEST: int_is_multiple_false
// EXPECT: false
print((7).isMultiple(of: 3))
// END

// TEST: int_signum_positive
// EXPECT: 1
print((42).signum())
// END

// TEST: int_signum_negative
// EXPECT: -1
print((-5).signum())
// END

// TEST: int_signum_zero
// EXPECT: 0
print((0).signum())
// END

// TEST: int_min_max_exist
// EXPECT: true
print(Int.min < Int.max)
// END

// === Double ===

// TEST: double_pi
// EXPECT: 3.141592653589793
print(Double.pi)
// END

// TEST: double_rounded
// EXPECT: 3.0
print((2.7).rounded())
// END

// TEST: double_square_root
// EXPECT: 3.0
print((9.0).squareRoot())
// END

// TEST: double_is_nan
// EXPECT: false
print((1.5).isNaN)
// END

// TEST: double_is_infinite
// EXPECT: true
print(Double.infinity.isInfinite)
// END

// TEST: double_is_finite
// EXPECT: true
print((1.5).isFinite)
// END

// TEST: double_is_zero
// EXPECT: true
print((0.0).isZero)
// END

// === Bool ===

// TEST: bool_toggle
// EXPECT: false
print(true.toggle())
// END

// === String ===

// TEST: string_drop_first
// EXPECT: llo
print("hello".dropFirst(2))
// END

// TEST: string_drop_last
// EXPECT: hel
print("hello".dropLast(2))
// END

// TEST: string_prefix
// EXPECT: hel
print("hello".prefix(3))
// END

// TEST: string_suffix
// EXPECT: llo
print("hello".suffix(3))
// END

// TEST: string_first_index
// EXPECT: 1
print("hello".firstIndex("e"))
// END

// === Array ===

// TEST: array_random_element_exists
// EXPECT: true
let arr = [1, 2, 3, 4, 5]
let r = arr.randomElement()
print(arr.contains(r))
// END

// TEST: array_first_index_found
// EXPECT: 2
print([10, 20, 30, 40].firstIndex(30))
// END

// TEST: array_first_index_not_found
// EXPECT: nil
print([10, 20, 30].firstIndex(99))
// END

// TEST: array_insert
// EXPECT: [1, 99, 2, 3]
var a = [1, 2, 3]
a = a.insert(99, 1)
print(a)
// END

// TEST: array_remove_all
// EXPECT: []
var b = [1, 2, 3]
b = b.removeAll()
print(b)
// END

// TEST: array_swap_at
// EXPECT: [3, 2, 1]
var c = [1, 2, 3]
c = c.swapAt(0, 2)
print(c)
// END

// === Dictionary ===

// TEST: dict_remove_all
// EXPECT: [:]
var d = ["a": 1, "b": 2]
d = d.removeAll()
print(d)
// END

// TEST: dict_merge
// EXPECT: 3
var d1 = ["a": 1]
d1 = d1.merge(["b": 2, "c": 3])
print(d1.count)
// END

// TEST: dict_map_values
// EXPECT: 6
let scores = ["a": 1, "b": 2, "c": 3]
let doubled = scores.mapValues { $0 * 2 }
print(doubled["c"]!)
// END
