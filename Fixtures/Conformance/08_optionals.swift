// Lantern Conformance Test Fixtures — Optionals
// Each test is run through both Lantern and the Swift compiler.
// Output must match exactly.

// TEST: optional_some
// EXPECT: Optional(42)
let x: Int? = 42
print(x as Any)
// END

// TEST: optional_none
// EXPECT: nil
let y: Int? = nil
print(y as Any)
// END

// TEST: force_unwrap_some
// EXPECT: 42
let a: Int? = 42
print(a!)
// END

// TEST: nil_coalescing
// EXPECT: 10
let b: Int? = nil
print(b ?? 10)
// END

// TEST: nil_coalescing_with_value
// EXPECT: 42
let c: Int? = 42
print(c ?? 10)
// END

// TEST: if_let_some
// EXPECT: Found: 42
let d: Int? = 42
if let value = d {
print("Found: \(value)")
} else {
print("Not found")
}
// END

// TEST: if_let_none
// EXPECT: Not found
let e: Int? = nil
if let value = e {
print("Found: \(value)")
} else {
print("Not found")
}
// END

// TEST: guard_let_some
// EXPECT: Value is 42
func check(_ opt: Int?) {
guard let value = opt else {
print("nil")
return
}
print("Value is \(value)")
}
check(42)
// END

// TEST: guard_let_none
// EXPECT: nil
func check2(_ opt: Int?) {
guard let value = opt else {
print("nil")
return
}
print("Value is \(value)")
}
check2(nil)
// END

// TEST: optional_chaining_some
// EXPECT: 5
let str: String? = "Hello"
print(str?.count ?? 0)
// END

// TEST: optional_chaining_none
// EXPECT: 0
let str2: String? = nil
print(str2?.count ?? 0)
// END

// TEST: optional_chaining_method
// EXPECT: HELLO
let str3: String? = "Hello"
print(str3?.uppercased() ?? "none")
// END

// TEST: optional_chaining_nil_method
// EXPECT: none
let str4: String? = nil
print(str4?.uppercased() ?? "none")
// END

// TEST: optional_comparison
// EXPECT: true
let f: Int? = 5
let g: Int? = 5
print(f == g)
// END

// TEST: optional_comparison_nil
// EXPECT: true
let h: Int? = nil
let i: Int? = nil
print(h == i)
// END

// TEST: optional_comparison_mixed
// EXPECT: false
let j: Int? = 5
let k: Int? = nil
print(j == k)
// END

// TEST: optional_in_array
// EXPECT: 2
let opts: [Int?] = [1, nil, 3]
var count = 0
for opt in opts {
if opt != nil {
count += 1
}
}
// nil counts as not-nil too, so count non-nil
count = 0
for opt in opts {
if let _ = opt {
count += 1
}
}
print(count)
// END

// TEST: nested_optional_chaining
// EXPECT: none
let outer: [String: [String: Int]]? = nil
let val = outer?["a"]?["b"] ?? -1
if val == -1 {
print("none")
} else {
print(val)
}
// END

// TEST: optional_map
// EXPECT: Optional(10)
let n: Int? = 5
let doubled = n.map { $0 * 2 }
print(doubled as Any)
// END

// TEST: optional_map_nil
// EXPECT: nil
let m: Int? = nil
let result = m.map { $0 * 2 }
print(result as Any)
// END

// TEST: optional_flatMap
// EXPECT: Optional(42)
let numStr: String? = "42"
let parsed = numStr.flatMap { Int($0) }
print(parsed as Any)
// END

// TEST: optional_flatMap_nil
// EXPECT: nil
let badStr: String? = "abc"
let parsed2 = badStr.flatMap { Int($0) }
print(parsed2 as Any)
// END

// TEST: multiple_if_let
// EXPECT: 3 Alice
let optA: Int? = 3
let optB: String? = "Alice"
if let a = optA, let b = optB {
print("\(a) \(b)")
} else {
print("missing")
}
// END

// TEST: multiple_if_let_one_nil
// EXPECT: missing
let optC: Int? = 3
let optD: String? = nil
if let c = optC, let d = optD {
print("\(c) \(d)")
} else {
print("missing")
}
// END

// TEST: optional_assignment
// EXPECT: Optional(10)
var opt: Int? = nil
opt = 10
print(opt as Any)
// END

// TEST: optional_set_to_nil
// EXPECT: nil
var opt2: Int? = 42
opt2 = nil
print(opt2 as Any)
// END

// TEST: dictionary_returns_optional
// EXPECT: found
let dict = ["key": "value"]
if let v = dict["key"] {
print("found")
} else {
print("not found")
}
// END

// TEST: array_first_is_optional
// EXPECT: 1
let arr = [1, 2, 3]
if let first = arr.first {
print(first)
}
// END