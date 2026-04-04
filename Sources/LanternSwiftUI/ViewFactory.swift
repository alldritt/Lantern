#if canImport(SwiftUI)
import SwiftUI
import LanternVM

/// Creates native SwiftUI views from interpreted type names and arguments.
public final class ViewFactory: @unchecked Sendable {

    private let vm: VM

    public init(vm: VM) {
        self.vm = vm
    }

    /// Create a SwiftUI view from a type name and arguments.
    /// Returns an AnyView and a ViewDescriptor for debugging.
    public func createView(
        typeName: String,
        arguments: [Value],
        location: SourceLocation = .unknown
    ) -> (AnyView, ViewDescriptor)? {
        var props: [String: Value] = [:]

        switch typeName {
        case "Text":
            let text = arguments.first?.stringValue ?? ""
            props["text"] = .string(text)
            return (AnyView(Text(text)),
                    ViewDescriptor(typeName: "Text", properties: props, modifiers: [],
                                   children: [], sourceLocation: location))

        case "Spacer":
            if let minLength = arguments.first?.doubleValue {
                return (AnyView(Spacer(minLength: CGFloat(minLength))),
                        ViewDescriptor(typeName: "Spacer", properties: ["minLength": .double(minLength)],
                                       modifiers: [], children: [], sourceLocation: location))
            }
            return (AnyView(Spacer()),
                    ViewDescriptor(typeName: "Spacer", properties: [:], modifiers: [],
                                   children: [], sourceLocation: location))

        case "Divider":
            return (AnyView(Divider()),
                    ViewDescriptor(typeName: "Divider", properties: [:], modifiers: [],
                                   children: [], sourceLocation: location))

        case "Image":
            let name = arguments.first?.stringValue ?? ""
            // Check if it's a system image (SF Symbol)
            if arguments.count == 1 {
                // Heuristic: if contains ".", likely system name
                props["systemName"] = .string(name)
                return (AnyView(Image(systemName: name)),
                        ViewDescriptor(typeName: "Image", properties: props, modifiers: [],
                                       children: [], sourceLocation: location))
            }
            props["name"] = .string(name)
            return (AnyView(Image(name)),
                    ViewDescriptor(typeName: "Image", properties: props, modifiers: [],
                                   children: [], sourceLocation: location))

        case "Label":
            let title = arguments.first?.stringValue ?? ""
            let systemImage = arguments.count > 1 ? arguments[1].stringValue ?? "" : ""
            props["title"] = .string(title)
            props["systemImage"] = .string(systemImage)
            return (AnyView(Label(title, systemImage: systemImage)),
                    ViewDescriptor(typeName: "Label", properties: props, modifiers: [],
                                   children: [], sourceLocation: location))

        case "ProgressView":
            if let value = arguments.first?.doubleValue {
                return (AnyView(ProgressView(value: value)),
                        ViewDescriptor(typeName: "ProgressView", properties: ["value": .double(value)],
                                       modifiers: [], children: [], sourceLocation: location))
            }
            return (AnyView(ProgressView()),
                    ViewDescriptor(typeName: "ProgressView", properties: [:], modifiers: [],
                                   children: [], sourceLocation: location))

        case "Color":
            if let name = arguments.first?.stringValue, let color = namedColor(name) {
                return (AnyView(color),
                        ViewDescriptor(typeName: "Color", properties: ["name": .string(name)],
                                       modifiers: [], children: [], sourceLocation: location))
            }
            return nil

        default:
            return nil
        }
    }

    /// Create a layout container (VStack, HStack, ZStack) wrapping child views.
    @MainActor
    public func createContainer(
        typeName: String,
        children: [AnyView],
        childDescriptors: [ViewDescriptor],
        arguments: [Value],
        location: SourceLocation = .unknown
    ) -> (AnyView, ViewDescriptor)? {
        var props: [String: Value] = [:]
        let spacing: CGFloat? = arguments.first?.doubleValue.map { CGFloat($0) }
        if let s = spacing { props["spacing"] = .double(Double(s)) }

        let descriptor = ViewDescriptor(
            typeName: typeName, properties: props, modifiers: [],
            children: childDescriptors, sourceLocation: location
        )

        let content = ChildrenView(children: children)

        switch typeName {
        case "VStack":
            let view = AnyView(VStack(spacing: spacing ?? 8) { content })
            return (view, descriptor)

        case "HStack":
            let view = AnyView(HStack(spacing: spacing ?? 8) { content })
            return (view, descriptor)

        case "ZStack":
            let view = AnyView(ZStack { content })
            return (view, descriptor)

        case "ScrollView":
            let view = AnyView(ScrollView { content })
            return (view, descriptor)

        case "Group":
            let view = AnyView(Group { content })
            return (view, descriptor)

        case "List":
            let view = AnyView(List { content })
            return (view, descriptor)

        case "NavigationStack":
            let view = AnyView(NavigationStack { content })
            return (view, descriptor)

        default:
            return nil
        }
    }

    /// Create a Button with an action closure and label content.
    public func createButton(
        title: String?,
        action: @escaping () -> Void,
        label: AnyView?,
        location: SourceLocation = .unknown
    ) -> (AnyView, ViewDescriptor) {
        let props: [String: Value] = title != nil ? ["title": .string(title!)] : [:]
        let descriptor = ViewDescriptor(
            typeName: "Button", properties: props, modifiers: [],
            children: [], sourceLocation: location
        )
        if let title = title {
            return (AnyView(Button(title, action: action)), descriptor)
        } else if let label = label {
            return (AnyView(Button(action: action) { label }), descriptor)
        } else {
            return (AnyView(Button("", action: action)), descriptor)
        }
    }

    /// Create a Toggle with a binding.
    public func createToggle(
        title: String,
        isOn: Binding<Bool>,
        location: SourceLocation = .unknown
    ) -> (AnyView, ViewDescriptor) {
        let descriptor = ViewDescriptor(
            typeName: "Toggle", properties: ["title": .string(title)], modifiers: [],
            children: [], sourceLocation: location
        )
        return (AnyView(Toggle(title, isOn: isOn)), descriptor)
    }

    /// Create a TextField with a binding.
    public func createTextField(
        title: String,
        text: Binding<String>,
        location: SourceLocation = .unknown
    ) -> (AnyView, ViewDescriptor) {
        let descriptor = ViewDescriptor(
            typeName: "TextField", properties: ["title": .string(title)], modifiers: [],
            children: [], sourceLocation: location
        )
        return (AnyView(TextField(title, text: text)), descriptor)
    }

    /// Create a Slider with a binding.
    public func createSlider(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        location: SourceLocation = .unknown
    ) -> (AnyView, ViewDescriptor) {
        let descriptor = ViewDescriptor(
            typeName: "Slider",
            properties: ["min": .double(range.lowerBound), "max": .double(range.upperBound)],
            modifiers: [], children: [], sourceLocation: location
        )
        return (AnyView(Slider(value: value, in: range)), descriptor)
    }

    // MARK: - Helpers

    private func namedColor(_ name: String) -> Color? {
        switch name.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "white": return .white
        case "black": return .black
        case "gray", "grey": return .gray
        case "clear": return .clear
        case "primary": return .primary
        case "secondary": return .secondary
        default: return nil
        }
    }
}

/// Wrapper to make [AnyView] usable in SwiftUI view builders.
private struct AnyViewArray: @unchecked Sendable {
    let views: [AnyView]
}

/// Helper view that renders an array of AnyViews as children.
struct ChildrenView: View {
    private let wrapped: AnyViewArray

    init(children: [AnyView]) {
        self.wrapped = AnyViewArray(views: children)
    }

    var body: some View {
        ForEach(Array(wrapped.views.enumerated()), id: \.offset) { _, child in
            child
        }
    }
}
#endif
