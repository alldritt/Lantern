// Lantern Conformance Test Fixtures — Higher-Order Functions
// Each test is run through both Lantern and the Swift compiler.
// Output must match exactly.

// TEST: map_integers
// EXPECT: [1, 4, 9, 16, 25]
print([1, 2, 3, 4, 5].map { $0 * $0 })
// END

// TEST: map_to_strings
// EXPECT: ["1", "2", "3"]
print([1, 2, 3].map { String($0) })
// END

// TEST: filter_even
// EXPECT: [2, 4, 6, 8, 10]
print((1...10).filter { $0 % 2 == 0 })
// END

// TEST: reduce_sum
// EXPECT: 55
print((1...10).reduce(0, +))
// END

// TEST: reduce_string
// EXPECT: a-b-c
let joined = ["a", "b", "c"].reduce("") { result, item in
result.isEmpty ? item : result + "-" + item
}
print(joined)
// END

// TEST: chained_map_filter
// EXPECT: [1, 9, 25]
let result = [1, 2, 3, 4, 5]
.filter { $0 % 2 != 0 }
.map { $0 * $0 }
print(result)
// END

// TEST: chained_map_filter_reduce
// EXPECT: 35
let total = [1, 2, 3, 4, 5]
.filter { $0 % 2 != 0 }
.map { $0 * $0 }
.reduce(0, +)
print(total)
// END

// TEST: sorted_by
// EXPECT: [5, 4, 3, 2, 1]
let desc = [3, 1, 4, 5, 2].sorted { $0 > $1 }
print(desc)
// END

// TEST: sorted_by_property
// EXPECT: Alice
// Bob
// Charlie
struct NamedItem {
let name: String
let priority: Int
}
let items = [
NamedItem(name: "Charlie", priority: 3),
NamedItem(name: "Alice", priority: 1),
NamedItem(name: "Bob", priority: 2)
]
for item in items.sorted(by: { $0.priority < $1.priority }) {
print(item.name)
}
// END

// TEST: contains_where
// EXPECT: true
let has = [1, 2, 3, 4, 5].contains { $0 > 3 }
print(has)
// END

// TEST: allSatisfy
// EXPECT: true
print([2, 4, 6, 8].allSatisfy { $0 % 2 == 0 })
// END

// TEST: allSatisfy_false
// EXPECT: false
print([2, 4, 5, 8].allSatisfy { $0 % 2 == 0 })
// END

// TEST: first_where
// EXPECT: Optional(4)
let first = [1, 2, 3, 4, 5].first { $0 > 3 }
print(first as Any)
// END

// TEST: compactMap
// EXPECT: [1, 2, 3]
let strings = ["1", "two", "2", "three", "3"]
let numbers = strings.compactMap { Int($0) }
print(numbers)
// END

// TEST: flatMap_arrays
// EXPECT: [1, 2, 3, 4, 5, 6]
let nested = [[1, 2], [3, 4], [5, 6]]
print(nested.flatMap { $0 })
// END

// TEST: forEach_with_side_effect
// EXPECT: 15
var sum = 0
[1, 2, 3, 4, 5].forEach { sum += $0 }
print(sum)
// END

// TEST: map_on_optional
// EXPECT: Optional(10)
let opt: Int? = 5
print(opt.map { $0 * 2 } as Any)
// END

// TEST: custom_higher_order
// EXPECT: [2, 6, 12]
func transform(_ items: [Int], using fn: (Int, Int) -> Int) -> [Int] {
var result: [Int] = []
for (index, item) in items.enumerated() {
result.append(fn(index + 1, item))
}
return result
}
print(transform([2, 3, 4]) { $0 * $1 })
// END

// TEST: function_composition
// EXPECT: 14
func pipe<A, B, C>(_ f: @escaping (A) -> B, _ g: @escaping (B) -> C) -> (A) -> C {
return { x in g(f(x)) }
}
let transform2 = pipe({ (x: Int) in x * 2 }, { (x: Int) in x + 4 })
print(transform2(5))
// END

// TEST: reduce_into
// EXPECT: 3
var counts: [String: Int] = [:]
let words = ["a", "b", "a", "c", "a"]
for word in words {
counts[word, default: 0] += 1
}
print(counts["a"]!)
// END

// TEST: zip_and_map
// EXPECT: [11, 22, 33]
let a = [1, 2, 3]
let b = [10, 20, 30]
let zipped = zip(a, b).map { $0 + $1 }
print(zipped)
// END

// TEST: prefix_and_suffix
// EXPECT: [1, 2, 3]
// [4, 5]
let nums = [1, 2, 3, 4, 5]
print(Array(nums.prefix(3)))
print(Array(nums.suffix(2)))
// END