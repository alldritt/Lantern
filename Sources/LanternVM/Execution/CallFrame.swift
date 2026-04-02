/// An activation record on the call stack.
public struct CallFrame: Sendable {
    public let function: FunctionRef
    public var ip: Int
    public let basePointer: Int
    public let captures: [Value]?

    public init(function: FunctionRef, ip: Int, basePointer: Int, captures: [Value]? = nil) {
        self.function = function; self.ip = ip
        self.basePointer = basePointer; self.captures = captures
    }
}
