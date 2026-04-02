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
        guard top > 0 else { return .nil_ } // graceful underflow
        top -= 1; return storage[top]
    }

    public func peek(_ distance: Int = 0) -> Value {
        let idx = top - 1 - distance
        guard idx >= 0 && idx < storage.count else { return .nil_ }
        return storage[idx]
    }

    public subscript(index: Int) -> Value {
        get {
            guard index >= 0 && index < top else { return .nil_ }
            return storage[index]
        }
        set {
            // Extend storage if needed
            while index >= storage.count {
                storage.append(contentsOf: Array(repeating: Value.nil_, count: max(storage.count, 16)))
            }
            if index >= top { top = index + 1 }
            storage[index] = newValue
        }
    }

    public var isEmpty: Bool { top == 0 }
    public var count: Int { top }
    public mutating func reset() { top = 0 }
    public mutating func truncate(to height: Int) {
        if height < 0 { top = 0 }
        else if height <= top { top = height }
        // if height > top, no-op (don't grow)
    }
}
