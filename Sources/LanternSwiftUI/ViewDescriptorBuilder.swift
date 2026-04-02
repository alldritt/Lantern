#if canImport(SwiftUI)
import LanternVM

/// Builds the descriptor tree during view construction.
public final class ViewDescriptorBuilder {
    private var stack: [(typeName: String, properties: [String: Value], modifiers: [ModifierDescriptor], location: SourceLocation)] = []
    private var childrenStack: [[ViewDescriptor]] = [[]]

    public init() {}

    public func beginView(typeName: String, properties: [String: Value], location: SourceLocation) {
        stack.append((typeName, properties, [], location))
        childrenStack.append([])
    }

    public func addModifier(_ modifier: ModifierDescriptor) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].modifiers.append(modifier)
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
}
#endif
