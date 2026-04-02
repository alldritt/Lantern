import LanternVM

/// A snapshot of a single call-stack frame for debugger display.
public struct FrameInfo: Sendable {
    public let functionName: String
    public let sourceLocation: SourceLocation?
    public let frameIndex: Int
    public let isHostFrame: Bool
    public let arguments: [(label: String?, value: Value)]

    public init(
        functionName: String,
        sourceLocation: SourceLocation?,
        frameIndex: Int,
        isHostFrame: Bool = false,
        arguments: [(label: String?, value: Value)] = []
    ) {
        self.functionName = functionName
        self.sourceLocation = sourceLocation
        self.frameIndex = frameIndex
        self.isHostFrame = isHostFrame
        self.arguments = arguments
    }
}
