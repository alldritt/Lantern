/// A fixed-capacity value stack for the VM.
public struct ValueStack: Sendable {
    public static let defaultMaxDepth = 65536
    private var storage: [Value]
    private let maxDepth: Int
    public private(set) var top: Int = 0

    public init(maxDepth: Int = Self.defaultMaxDepth) {
        self.maxDepth = maxDepth
        self.storage = Array(repeating: .nil_, count: min(256, maxDepth))
    }

    public mutating func push(_ value: Value) throws {
        if top >= maxDepth { throw InterpreterError.stackOverflow() }
        if top >= storage.count {
            storage.append(contentsOf: Array(repeating: Value.nil_, count: storage.count))
        }
        storage[top] = value; top += 1
    }

    @discardableResult
    public mutating func pop() -> Value {
        precondition(top > 0, "Stack underflow")
        top -= 1; return storage[top]
    }

    public func peek(_ distance: Int = 0) -> Value {
        precondition(top - 1 - distance >= 0, "Stack peek underflow")
        return storage[top - 1 - distance]
    }

    public subscript(index: Int) -> Value {
        get { precondition(index >= 0 && index < top); return storage[index] }
        set { precondition(index >= 0 && index < top); storage[index] = newValue }
    }

    public var isEmpty: Bool { top == 0 }
    public var count: Int { top }
    public mutating func reset() { top = 0 }
    public mutating func truncate(to height: Int) { precondition(height >= 0 && height <= top); top = height }
}
