#if canImport(SwiftUI)
import LanternVM

/// Builds the descriptor tree during view construction.
public final class ViewDescriptorBuilder: DescriptorBuilderProtocol, @unchecked Sendable {
    private var stack: [(typeName: String, properties: [String: Value], modifiers: [ModifierDescriptor], location: SourceLocation)] = []
    private var childrenStack: [[ViewDescriptor]] = [[]]

    /// Called after the view tree is fully built (after the root endView).
    public var onTreeBuilt: ((ViewDescriptor?) -> Void)?

    public init() {}

    public func beginView(typeName: String, properties: [String: Value], location: SourceLocation) {
        stack.append((typeName, properties, [], location))
        childrenStack.append([])
    }

    public func addModifier(_ modifier: ModifierDescriptor) {
        // Modifiers apply to the most recently completed view (the last child
        // in the current children list), not to the container being built.
        // This matches how SwiftUI modifier chaining works:
        //   Text("hi").font(.title)  →  Text is completed, then .font attaches to it
        guard let lastIdx = childrenStack.indices.last,
              !childrenStack[lastIdx].isEmpty else { return }
        let idx = childrenStack[lastIdx].count - 1
        var desc = childrenStack[lastIdx][idx]
        desc = ViewDescriptor(
            typeName: desc.typeName,
            properties: desc.properties,
            modifiers: desc.modifiers + [modifier],
            children: desc.children,
            sourceLocation: desc.sourceLocation
        )
        childrenStack[lastIdx][idx] = desc
    }

    /// Protocol conformance — creates a ModifierDescriptor from raw values.
    public func addModifier(name: String, arguments: [String: Value], location: SourceLocation) {
        addModifier(ModifierDescriptor(name: name, arguments: arguments, sourceLocation: location))
    }

    public func endView() {
        guard let current = stack.popLast() else { return }
        let children = childrenStack.popLast() ?? []
        let descriptor = ViewDescriptor(
            typeName: current.typeName,
            properties: current.properties,
            modifiers: current.modifiers,
            children: children,
            sourceLocation: current.location
        )
        if childrenStack.isEmpty {
            childrenStack.append([descriptor])
        } else {
            childrenStack[childrenStack.count - 1].append(descriptor)
        }
    }

    public var rootDescriptor: ViewDescriptor? {
        childrenStack.first?.first
    }

    public func reset() {
        stack.removeAll()
        childrenStack = [[]]
    }

    /// Protocol conformance — converts the tree to VM-level descriptors.
    public var rootViewDescriptor: VMViewDescriptor? {
        rootDescriptor.map { Self.convertToVM($0) }
    }

    private static func convertToVM(_ desc: ViewDescriptor) -> VMViewDescriptor {
        VMViewDescriptor(
            typeName: desc.typeName,
            properties: desc.properties,
            modifierNames: desc.modifiers.map(\.name),
            children: desc.children.map { convertToVM($0) }
        )
    }
}
#endif
