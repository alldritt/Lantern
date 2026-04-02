// Lantern Conformance Test Fixtures — Arrays
// Each test is run through both Lantern and the Swift compiler.
// Output must match exactly.

// TEST: array_literal
// EXPECT: [1, 2, 3]
let nums = [1, 2, 3]
print(nums)
// END

// TEST: empty_array
// EXPECT: []
let empty: [Int] = []
print(empty)
// END

// TEST: array_subscript_read
// EXPECT: 20
let items = [10, 20, 30]
print(items[1])
// END

// TEST: array_subscript_write
// EXPECT: [10, 99, 30]
var arr = [10, 20, 30]
arr[1] = 99
print(arr)
// END

// TEST: array_count
// EXPECT: 4
print([1, 2, 3, 4].count)
// END

// TEST: array_isEmpty_false
// EXPECT: false
print([1].isEmpty)
// END

// TEST: array_isEmpty_true
// EXPECT: true
let e: [Int] = []
print(e.isEmpty)
// END

// TEST: array_append
// EXPECT: [1, 2, 3, 4]
var a = [1, 2, 3]
a.append(4)
print(a)
// END

// TEST: array_append_multiple
// EXPECT: 5
var b: [Int] = []
b.append(10)
b.append(20)
b.append(30)
b.append(40)
b.append(50)
print(b.count)
// END

// TEST: array_remove
// EXPECT: [1, 3]
var c = [1, 2, 3]
c.remove(at: 1)
print(c)
// END

// TEST: array_contains_true
// EXPECT: true
print([1, 2, 3].contains(2))
// END

// TEST: array_contains_false
// EXPECT: false
print([1, 2, 3].contains(5))
// END

// TEST: array_first
// EXPECT: Optional(1)
print([1, 2, 3].first as Any)
// END

// TEST: array_last
// EXPECT: Optional(3)
print([1, 2, 3].last as Any)
// END

// TEST: array_first_empty
// EXPECT: nil
let emptyArr: [Int] = []
print(emptyArr.first as Any)
// END

// TEST: for_in_array
// EXPECT: a
// b
// c
let letters = ["a", "b", "c"]
for letter in letters {
print(letter)
}
// END

// TEST: for_in_array_with_index
// EXPECT: 0: a
// 1: b
// 2: c
let words = ["a", "b", "c"]
for i in 0..<words.count {
print("\(i): \(words[i])")
}
// END

// TEST: array_map
// EXPECT: [2, 4, 6]
let original = [1, 2, 3]
let doubled = original.map { $0 * 2 }
print(doubled)
// END

// TEST: array_filter
// EXPECT: [2, 4, 6]
let all = [1, 2, 3, 4, 5, 6]
let evens = all.filter { $0 % 2 == 0 }
print(evens)
// END

// TEST: array_sorted
// EXPECT: [1, 2, 3, 4, 5]
let unsorted = [3, 1, 4, 5, 2]
print(unsorted.sorted())
// END

// TEST: array_reversed
// EXPECT: [3, 2, 1]
let forward = [1, 2, 3]
print(Array(forward.reversed()))
// END

// TEST: array_reduce
// EXPECT: 15
let numbers = [1, 2, 3, 4, 5]
let sum = numbers.reduce(0) { $0 + $1 }
print(sum)
// END

// TEST: nested_array
// EXPECT: 6
let matrix = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
print(matrix[1][2])
// END

// TEST: array_of_strings
// EXPECT: hello world
let parts = ["hello", "world"]
print(parts.joined(separator: " "))
// END

// TEST: array_build_in_loop
// EXPECT: [0, 1, 4, 9, 16]
var squares: [Int] = []
for i in 0..<5 {
squares.append(i * i)
}
print(squares)
// END

// TEST: array_equality
// EXPECT: true
print([1, 2, 3] == [1, 2, 3])
// END

// TEST: array_inequality
// EXPECT: true
print([1, 2, 3] != [1, 2, 4])
// END

// TEST: array_string_interpolation
// EXPECT: Items: [1, 2, 3]
let list = [1, 2, 3]
print("Items: \(list)")
// END

// TEST: array_forEach
// EXPECT: 1
// 2
// 3
[1, 2, 3].forEach { print($0) }
// END

// TEST: array_compactMap
// EXPECT: [1, 3]
let mixed: [Int?] = [1, nil, 3, nil]
let compact = mixed.compactMap { $0 }
print(compact)
// END

// TEST: array_flatMap
// EXPECT: [1, 2, 3, 4, 5, 6]
let nested = [[1, 2], [3, 4], [5, 6]]
print(nested.flatMap { $0 })
// END

// TEST: array_enumerated
// EXPECT: 0: a
// 1: b
// 2: c
for (index, value) in ["a", "b", "c"].enumerated() {
print("\(index): \(value)")
}
// END

// TEST: array_min_max
// EXPECT: 1
// 5
let vals = [3, 1, 4, 1, 5]
print(vals.min()!)
print(vals.max()!)
// END