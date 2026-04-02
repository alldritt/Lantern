// Lantern Conformance Test Fixtures — Complex Programs
// Each test exercises multiple language features together.
// Output must match exactly.

// TEST: todo_list
// EXPECT: 2 pending tasks:
// - Buy groceries
// - Write report
struct Todo {
let title: String
var isDone: Bool
}
var todos = [
Todo(title: "Buy groceries", isDone: false),
Todo(title: "Call dentist", isDone: true),
Todo(title: "Write report", isDone: false)
]
let pending = todos.filter { !$0.isDone }
print("\(pending.count) pending tasks:")
for todo in pending {
print("- \(todo.title)")
}
// END

// TEST: stack_implementation
// EXPECT: 3
// 2
// 1
// empty: true
struct Stack<T> {
var items: [T] = []
var isEmpty: Bool { items.isEmpty }
var count: Int { items.count }
mutating func push(_ item: T) { items.append(item) }
mutating func pop() -> T? {
return items.isEmpty ? nil : items.removeLast()
}
func peek() -> T? { items.last }
}
var stack = Stack<Int>()
stack.push(1)
stack.push(2)
stack.push(3)
while let item = stack.pop() {
print(item)
}
print("empty: \(stack.isEmpty)")
// END

// TEST: word_frequency
// EXPECT: the: 3
// cat: 2
let words = ["the", "cat", "sat", "on", "the", "mat", "the", "cat"]
var freq: [String: Int] = [:]
for word in words {
freq[word, default: 0] += 1
}
let sorted = freq.sorted { $0.value > $1.value }
for (word, count) in sorted.prefix(2) {
print("\(word): \(count)")
}
// END

// TEST: fibonacci_sequence
// EXPECT: [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
func fibSequence(_ count: Int) -> [Int] {
if count <= 0 { return [] }
if count == 1 { return [0] }
var fibs = [0, 1]
for _ in 2..<count {
fibs.append(fibs[fibs.count - 1] + fibs[fibs.count - 2])
}
return fibs
}
print(fibSequence(10))
// END

// TEST: binary_search
// EXPECT: found at index 4
func binarySearch(_ arr: [Int], target: Int) -> Int? {
var low = 0
var high = arr.count - 1
while low <= high {
let mid = (low + high) / 2
if arr[mid] == target {
return mid
} else if arr[mid] < target {
low = mid + 1
} else {
high = mid - 1
}
}
return nil
}
let sorted2 = [2, 5, 8, 12, 16, 23, 38, 56, 72, 91]
if let index = binarySearch(sorted2, target: 16) {
print("found at index \(index)")
} else {
print("not found")
}
// END

// TEST: state_machine
// EXPECT: idle -> running
// running -> paused
// paused -> running
// running -> stopped
enum MachineState {
case idle, running, paused, stopped
}
struct Machine {
var state: MachineState = .idle

mutating func transition(to newState: MachineState) -> Bool {
let valid: Bool
switch (state, newState) {
case (.idle, .running),
     (.running, .paused),
     (.running, .stopped),
     (.paused, .running):
    valid = true
default:
    valid = false
}
if valid {
print("\(state) -> \(newState)")
state = newState
}
return valid
}

}
var m = Machine()
m.transition(to: .running)
m.transition(to: .paused)
m.transition(to: .running)
m.transition(to: .stopped)
// END

// TEST: calculator
// EXPECT: 7.0
// 3.0
// 10.0
// 5.0
enum Operation {
case add, subtract, multiply, divide
}
func calculate(_ a: Double, _ op: Operation, _ b: Double) -> Double? {
switch op {
case .add: return a + b
case .subtract: return a - b
case .multiply: return a * b
case .divide:
if b == 0 { return nil }
return a / b
}
}
print(calculate(3, .add, 4)!)
print(calculate(10, .subtract, 7)!)
print(calculate(2, .multiply, 5)!)
print(calculate(10, .divide, 2)!)
// END

// TEST: linked_list_count
// EXPECT: 3
indirect enum LinkedList<T> {
case empty
case node(T, LinkedList<T>)
}
func count<T>(_ list: LinkedList<T>) -> Int {
switch list {
case .empty:
return 0
case .node(_, let next):
return 1 + count(next)
}
}
let list: LinkedList<Int> = .node(1, .node(2, .node(3, .empty)))
print(count(list))
// END

// TEST: grade_calculator
// EXPECT: Alice: B (85.0)
// Bob: A (92.0)
// Charlie: C (73.0)
struct Student {
let name: String
var scores: [Int]
var average: Double {
guard !scores.isEmpty else { return 0 }
return Double(scores.reduce(0, +)) / Double(scores.count)
}
var grade: String {
switch average {
case 90...: return "A"
case 80..<90: return "B"
case 70..<80: return "C"
case 60..<70: return "D"
default: return "F"
}
}
}
let students = [
Student(name: "Alice", scores: [80, 90, 85]),
Student(name: "Bob", scores: [95, 88, 93]),
Student(name: "Charlie", scores: [70, 75, 74])
]
for s in students {
print("\(s.name): \(s.grade) (\(s.average))")
}
// END

// TEST: event_system
// EXPECT: Logger: user_login
// Analytics: user_login
// Logger: page_view
// Analytics: page_view
protocol EventHandler {
var name: String { get }
func handle(event: String)
}
struct Logger: EventHandler {
let name = "Logger"
func handle(event: String) {
print("Logger: \(event)")
}
}
struct Analytics: EventHandler {
let name = "Analytics"
func handle(event: String) {
print("Analytics: \(event)")
}
}
struct EventBus {
var handlers: [EventHandler] = []
mutating func register(_ handler: EventHandler) {
handlers.append(handler)
}
func emit(_ event: String) {
for handler in handlers {
handler.handle(event: event)
}
}
}
var bus = EventBus()
bus.register(Logger())
bus.register(Analytics())
bus.emit("user_login")
bus.emit("page_view")
// END

// TEST: result_type_pattern
// EXPECT: success: 42
// failure: not found
enum AppError: Error {
case notFound
case unauthorized
}
func fetchData(id: Int) -> Result<Int, AppError> {
if id > 0 {
return .success(id * 42)
} else {
return .failure(.notFound)
}
}
switch fetchData(id: 1) {
case .success(let value):
print("success: \(value)")
case .failure(let error):
print("failure: \(error)")
}
switch fetchData(id: -1) {
case .success(let value):
print("success: \(value)")
case .failure:
print("failure: not found")
}
// END

// TEST: matrix_operations
// EXPECT: [[1, 4], [2, 5], [3, 6]]
func transpose(_ matrix: [[Int]]) -> [[Int]] {
guard let firstRow = matrix.first else { return [] }
var result: [[Int]] = Array(repeating: [], count: firstRow.count)
for row in matrix {
for (col, val) in row.enumerated() {
result[col].append(val)
}
}
return result
}
let m = [[1, 2, 3], [4, 5, 6]]
print(transpose(m))
// END

// TEST: pipeline_processing
// EXPECT: ALICE, BOB, DAVID
let names = ["alice", "bob", "charlie", "david"]
let result = names
.filter { $0.count <= 5 }
.map { $0.uppercased() }
.sorted()
print(result.joined(separator: ", "))
// END

// TEST: recursive_tree_sum
// EXPECT: 15
indirect enum Tree {
case leaf(Int)
case branch(Tree, Tree)
}
func sum(_ tree: Tree) -> Int {
switch tree {
case .leaf(let value):
return value
case .branch(let left, let right):
return sum(left) + sum(right)
}
}
let tree: Tree = .branch(
.branch(.leaf(1), .leaf(2)),
.branch(.leaf(3), .branch(.leaf(4), .leaf(5)))
)
print(sum(tree))
// END

// TEST: error_handling_with_cleanup
// EXPECT: opening connection
// performing work
// closing connection
// caught: simulated
enum NetError: Error { case simulated }
func riskyWork() throws {
print("opening connection")
defer { print("closing connection") }
print("performing work")
throw NetError.simulated
}
do {
try riskyWork()
} catch {
print("caught: simulated")
}
// END

// TEST: builder_pattern
// EXPECT: GET https://api.example.com?limit=10&page=1
struct Request {
var method: String = "GET"
var url: String = ""
var params: [String: String] = [:]

func build() -> String {
var result = "\(method) \(url)"
if !params.isEmpty {
let query = params.sorted { $0.key < $1.key }
    .map { "\($0.key)=\($0.value)" }
    .joined(separator: "&")
result += "?\(query)"
}
return result
}

}
var req = Request()
req.url = "https://api.example.com"
req.params["page"] = "1"
req.params["limit"] = "10"
print(req.build())
// END

// TEST: closure_state_machine
// EXPECT: 1
// 2
// 3
// 4
// 5
func makeSequence(from start: Int, to end: Int) -> () -> Int? {
var current = start
return {
guard current <= end else { return nil }
let value = current
current += 1
return value
}
}
let next = makeSequence(from: 1, to: 5)
while let value = next() {
print(value)
}
// END