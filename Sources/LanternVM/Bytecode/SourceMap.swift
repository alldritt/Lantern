/// Maps bytecode offsets to source locations and vice versa.
public struct SourceMap: Sendable {
    public var files: [String] = []
    public private(set) var entries: [(bytecodeOffset: Int, location: SourceLocation)] = []

    public init() {}

    @discardableResult
    public mutating func addFile(_ name: String) -> UInt16 {
        if let i = files.firstIndex(of: name) { return UInt16(i) }
        let i = files.count; files.append(name); return UInt16(i)
    }

    public mutating func add(bytecodeOffset: Int, location: SourceLocation) {
        if let last = entries.last, last.location == location { return }
        entries.append((bytecodeOffset: bytecodeOffset, location: location))
    }

    /// Find the source location for a bytecode offset (binary search).
    public func location(forOffset offset: Int) -> SourceLocation? {
        guard !entries.isEmpty else { return nil }
        var lo = 0, hi = entries.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if entries[mid].bytecodeOffset == offset { return entries[mid].location }
            else if entries[mid].bytecodeOffset < offset { lo = mid + 1 }
            else { hi = mid - 1 }
        }
        return hi >= 0 ? entries[hi].location : entries[0].location
    }

    /// Find all bytecode offsets that map to a given source line.
    public func offsets(forLine line: UInt32, fileIndex: UInt16 = 0) -> [Int] {
        entries.filter { $0.location.line == line && $0.location.fileIndex == fileIndex }
            .map(\.bytecodeOffset)
    }

    /// Find the first executable bytecode offset at or after the given line.
    public func firstExecutableOffset(atOrAfterLine line: UInt32, fileIndex: UInt16 = 0) -> (offset: Int, line: UInt32)? {
        let matching = entries
            .filter { $0.location.fileIndex == fileIndex && $0.location.line >= line }
            .sorted(by: { $0.location.line < $1.location.line })
        guard let first = matching.first else { return nil }
        return (offset: first.bytecodeOffset, line: first.location.line)
    }
}
