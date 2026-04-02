/// A position in source code.
public struct SourceLocation: Equatable, Hashable, Sendable, CustomStringConvertible {
    public let fileIndex: UInt16
    public let line: UInt32
    public let column: UInt16

    public init(fileIndex: UInt16 = 0, line: UInt32, column: UInt16) {
        self.fileIndex = fileIndex
        self.line = line
        self.column = column
    }

    public static let unknown = SourceLocation(fileIndex: 0, line: 0, column: 0)

    public var description: String { "line \(line), column \(column)" }

    public func description(files: [String]) -> String {
        let file = Int(fileIndex) < files.count ? files[Int(fileIndex)] : "<unknown>"
        return "\(file):\(line):\(column)"
    }
}
