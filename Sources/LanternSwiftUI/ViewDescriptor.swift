#if canImport(SwiftUI)
import LanternVM

/// A lightweight mirror of the SwiftUI view tree for debugging and design tooling.
public struct ViewDescriptor: Sendable {
    public let typeName: String
    public let properties: [String: Value]
    public let modifiers: [ModifierDescriptor]
    public let children: [ViewDescriptor]
    public let sourceLocation: SourceLocation

    public init(
        typeName: String,
        properties: [String: Value] = [:],
        modifiers: [ModifierDescriptor] = [],
        children: [ViewDescriptor] = [],
        sourceLocation: SourceLocation = .unknown
    ) {
        self.typeName = typeName; self.properties = properties
        self.modifiers = modifiers; self.children = children
        self.sourceLocation = sourceLocation
    }

    public var totalViewCount: Int {
        1 + children.reduce(0) { $0 + $1.totalViewCount }
    }

    public func flattened() -> [ViewDescriptor] {
        [self] + children.flatMap { $0.flattened() }
    }

    public func descriptor(at location: SourceLocation) -> ViewDescriptor? {
        if sourceLocation == location { return self }
        for child in children {
            if let found = child.descriptor(at: location) { return found }
        }
        return nil
    }

    /// Debug dump of the tree for diagnostics.
    public func debugDump(indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        var result = "\(pad)\(typeName)"
        if !modifiers.isEmpty {
            result += " [\(modifiers.map(\.name).joined(separator: ", "))]"
        }
        result += " (\(children.count) children)\n"
        for child in children {
            result += child.debugDump(indent: indent + 1)
        }
        return result
    }
}

/// Describes a modifier applied to a view.
public struct ModifierDescriptor: Sendable {
    public let name: String
    public let arguments: [String: Value]
    public let sourceLocation: SourceLocation

    public init(name: String, arguments: [String: Value] = [:], sourceLocation: SourceLocation = .unknown) {
        self.name = name; self.arguments = arguments; self.sourceLocation = sourceLocation
    }
}
#endif
