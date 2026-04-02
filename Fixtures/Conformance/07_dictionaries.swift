// Lantern Conformance Test Fixtures — Dictionaries
// Each test is run through both Lantern and the Swift compiler.
// Output must match exactly.

// TEST: dictionary_literal
// EXPECT: 2
let ages = ["Alice": 30, "Bob": 25]
print(ages.count)
// END

// TEST: empty_dictionary
// EXPECT: 0
let empty: [String: Int] = [:]
print(empty.count)
// END

// TEST: dictionary_subscript_read
// EXPECT: Optional(30)
let scores = ["math": 90, "science": 85, "english": 30]
print(scores["english"] as Any)
// END

// TEST: dictionary_subscript_missing
// EXPECT: nil
let d = ["a": 1, "b": 2]
print(d["c"] as Any)
// END

// TEST: dictionary_subscript_write
// EXPECT: 99
var grades: [String: Int] = ["math": 85]
grades["math"] = 99
print(grades["math"]!)
// END

// TEST: dictionary_insert
// EXPECT: 2
var dict: [String: Int] = ["a": 1]
dict["b"] = 2
print(dict.count)
// END

// TEST: dictionary_remove
// EXPECT: nil
var removable = ["a": 1, "b": 2]
removable.removeValue(forKey: "a")
print(removable["a"] as Any)
// END

// TEST: dictionary_isEmpty_true
// EXPECT: true
let emptyDict: [String: Int] = [:]
print(emptyDict.isEmpty)
// END

// TEST: dictionary_isEmpty_false
// EXPECT: false
print(["a": 1].isEmpty)
// END

// TEST: dictionary_count
// EXPECT: 3
let three = ["a": 1, "b": 2, "c": 3]
print(three.count)
// END

// TEST: dictionary_keys_count
// EXPECT: 3
let kd = ["x": 10, "y": 20, "z": 30]
print(kd.keys.count)
// END

// TEST: dictionary_values_sum
// EXPECT: 60
let vd = ["x": 10, "y": 20, "z": 30]
var sum = 0
for v in vd.values {
sum += v
}
print(sum)
// END

// TEST: dictionary_update_existing
// EXPECT: 100
var updateMe = ["score": 50]
updateMe["score"] = 100
print(updateMe["score"]!)
// END

// TEST: dictionary_default_value
// EXPECT: 0
let lookup: [String: Int] = ["a": 1]
print(lookup["b", default: 0])
// END

// TEST: dictionary_iteration_count
// EXPECT: 3
let iterDict = ["a": 1, "b": 2, "c": 3]
var count = 0
for _ in iterDict {
count += 1
}
print(count)
// END

// TEST: dictionary_build_in_loop
// EXPECT: 5
var built: [Int: Int] = [:]
for i in 0..<5 {
built[i] = i * i
}
print(built.count)
// END

// TEST: dictionary_contains_key
// EXPECT: true
// false
let check = ["a": 1, "b": 2]
print(check["a"] != nil)
print(check["c"] != nil)
// END

// TEST: dictionary_merge_loop
// EXPECT: 4
var base = ["a": 1, "b": 2]
let extra = ["c": 3, "d": 4]
for (key, value) in extra {
base[key] = value
}
print(base.count)
// END

// TEST: dictionary_of_arrays
// EXPECT: 3
let groups: [String: [Int]] = ["odds": [1, 3, 5], "evens": [2, 4, 6]]
print(groups["odds"]!.count)
// END

// TEST: nested_dictionary
// EXPECT: 42
let nested: [String: [String: Int]] = [
"outer": ["inner": 42]
]
print(nested["outer"]!["inner"]!)
// END

// TEST: dictionary_string_interpolation
// EXPECT: 2
let info = ["name": "Alice", "city": "Victoria"]
print(info.count)
// END

// TEST: dictionary_compactMapValues
// EXPECT: 2
let mixed: [String: Int?] = ["a": 1, "b": nil, "c": 3]
let compact = mixed.compactMapValues { $0 }
print(compact.count)
// END