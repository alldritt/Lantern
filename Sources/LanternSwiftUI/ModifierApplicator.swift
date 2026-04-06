#if canImport(SwiftUI)
import SwiftUI
import LanternVM

/// Applies SwiftUI modifiers to an AnyView by name and arguments.
public struct ModifierApplicator {

    /// Apply a named modifier with arguments to a view.
    /// Returns the modified AnyView and a ModifierDescriptor for debugging.
    public static func apply(
        _ name: String,
        arguments: [Value],
        to view: AnyView,
        location: SourceLocation = .unknown
    ) -> (AnyView, ModifierDescriptor) {
        let argDict = argumentDict(from: arguments, for: name)
        let descriptor = ModifierDescriptor(name: name, arguments: argDict, sourceLocation: location)

        let modified: AnyView
        switch name {
        // Layout
        case "padding":
            if arguments.count >= 2,
               let edgeName = SwiftUIConstants.caseName(from: arguments[0]),
               let amount = arguments[1].doubleValue {
                // .padding(.top, 10) or .padding(.horizontal, 20)
                let edges = Self.edgeSet(from: edgeName)
                modified = AnyView(view.padding(edges, CGFloat(amount)))
            } else if let value = arguments.first?.doubleValue {
                modified = AnyView(view.padding(CGFloat(value)))
            } else if let edgeName = arguments.first.flatMap({ SwiftUIConstants.caseName(from: $0) }) {
                // .padding(.horizontal) — edge with default amount
                let edges = Self.edgeSet(from: edgeName)
                modified = AnyView(view.padding(edges))
            } else {
                modified = AnyView(view.padding())
            }

        case "frame":
            // Supports: .frame(width:height:), .frame(minWidth:maxWidth:minHeight:maxHeight:alignment:)
            // Also: .frame(maxWidth: .infinity) via special .infinity enum case
            let width = arguments.first { argNamed($0, "width") }?.doubleValue.map { CGFloat($0) }
            let height = arguments.first { argNamed($0, "height") }?.doubleValue.map { CGFloat($0) }
            let maxWidth = Self.dimensionValue(from: arguments, named: "maxWidth")
            let maxHeight = Self.dimensionValue(from: arguments, named: "maxHeight")
            let minWidth = Self.dimensionValue(from: arguments, named: "minWidth")
            let minHeight = Self.dimensionValue(from: arguments, named: "minHeight")
            if maxWidth != nil || maxHeight != nil || minWidth != nil || minHeight != nil {
                modified = AnyView(view.frame(
                    minWidth: minWidth, maxWidth: maxWidth,
                    minHeight: minHeight, maxHeight: maxHeight
                ))
            } else {
                modified = AnyView(view.frame(width: width, height: height))
            }

        case "fixedSize":
            modified = AnyView(view.fixedSize())

        case "offset":
            let x = arguments.first?.doubleValue ?? 0
            let y = arguments.count > 1 ? arguments[1].doubleValue ?? 0 : 0
            modified = AnyView(view.offset(x: CGFloat(x), y: CGFloat(y)))

        case "position":
            let x = arguments.first?.doubleValue ?? 0
            let y = arguments.count > 1 ? arguments[1].doubleValue ?? 0 : 0
            modified = AnyView(view.position(x: CGFloat(x), y: CGFloat(y)))

        // Typography
        case "font":
            if case .enumCase(let ref) = arguments.first, ref.typeName == "Font" {
                modified = AnyView(view.font(systemFont(ref.caseName)))
            } else if let fontName = arguments.first?.stringValue {
                modified = AnyView(view.font(systemFont(fontName)))
            } else {
                modified = AnyView(view.font(.body))
            }

        case "bold":
            modified = AnyView(view.bold())

        case "italic":
            modified = AnyView(view.italic())

        case "underline":
            modified = AnyView(view.underline())

        case "strikethrough":
            modified = AnyView(view.strikethrough())

        case "lineLimit":
            let limit = arguments.first?.intValue
            modified = AnyView(view.lineLimit(limit))

        case "multilineTextAlignment":
            let alignment = arguments.first.map { Self.textAlignmentFromValue($0) } ?? .leading
            modified = AnyView(view.multilineTextAlignment(alignment))

        // Appearance
        case "foregroundColor", "foregroundStyle":
            if let arg = arguments.first, let color = Self.colorFromValue(arg) {
                modified = AnyView(view.foregroundStyle(color))
            } else {
                modified = AnyView(view)
            }

        case "background":
            if let arg = arguments.first, let color = Self.colorFromValue(arg) {
                modified = AnyView(view.background(color))
            } else if let arg = arguments.first, let (_, box) = unboxView(arg) {
                modified = AnyView(view.background(box.view))
            } else {
                modified = AnyView(view)
            }

        case "overlay":
            if let arg = arguments.first, let color = Self.colorFromValue(arg) {
                modified = AnyView(view.overlay(color))
            } else if let arg = arguments.first, let (_, box) = unboxView(arg) {
                modified = AnyView(view.overlay(box.view))
            } else {
                modified = AnyView(view)
            }

        case "opacity":
            let value = arguments.first?.doubleValue ?? 1.0
            modified = AnyView(view.opacity(value))

        case "cornerRadius":
            let radius = arguments.first?.doubleValue ?? 0
            modified = AnyView(view.clipShape(RoundedRectangle(cornerRadius: CGFloat(radius))))

        case "clipShape":
            let name = arguments.first.flatMap { SwiftUIConstants.caseName(from: $0) } ?? "rectangle"
            switch name.lowercased() {
            case "circle": modified = AnyView(view.clipShape(Circle()))
            case "capsule": modified = AnyView(view.clipShape(Capsule()))
            case "ellipse": modified = AnyView(view.clipShape(Ellipse()))
            default: modified = AnyView(view.clipShape(Rectangle()))
            }

        case "shadow":
            let radius = arguments.first?.doubleValue ?? 5
            modified = AnyView(view.shadow(radius: CGFloat(radius)))

        case "border":
            if let arg = arguments.first, let color = Self.colorFromValue(arg) {
                let width = arguments.count > 1 ? arguments[1].doubleValue ?? 1 : 1
                modified = AnyView(view.border(color, width: CGFloat(width)))
            } else {
                modified = AnyView(view)
            }

        // Transforms
        case "rotationEffect":
            let degrees = arguments.first?.doubleValue ?? 0
            modified = AnyView(view.rotationEffect(.degrees(degrees)))

        case "scaleEffect":
            let scale = arguments.first?.doubleValue ?? 1.0
            modified = AnyView(view.scaleEffect(CGFloat(scale)))

        // Visibility / Interaction
        case "hidden":
            modified = AnyView(view.hidden())

        case "disabled":
            let disabled = arguments.first?.boolValue ?? true
            modified = AnyView(view.disabled(disabled))

        // Navigation
        case "navigationTitle":
            let title = arguments.first?.stringValue ?? ""
            modified = AnyView(view.navigationTitle(title))

        // Image modifiers
        case "resizable":
            modified = AnyView(view) // resizable is Image-specific; AnyView erases it
            // Note: For real resizable support, Image would need special handling

        case "scaledToFit":
            modified = AnyView(view.aspectRatio(contentMode: .fit))

        case "scaledToFill":
            modified = AnyView(view.aspectRatio(contentMode: .fill))

        case "aspectRatio":
            let mode = arguments.first.flatMap { SwiftUIConstants.caseName(from: $0) } ?? "fit"
            if mode.lowercased() == "fill" {
                modified = AnyView(view.aspectRatio(contentMode: .fill))
            } else {
                modified = AnyView(view.aspectRatio(contentMode: .fit))
            }

        case "imageScale":
            let scale = arguments.first.flatMap { SwiftUIConstants.caseName(from: $0) } ?? "medium"
            switch scale.lowercased() {
            case "small": modified = AnyView(view.imageScale(.small))
            case "large": modified = AnyView(view.imageScale(.large))
            default: modified = AnyView(view.imageScale(.medium))
            }

        case "renderingMode":
            let mode = arguments.first.flatMap { SwiftUIConstants.caseName(from: $0) } ?? "original"
            switch mode.lowercased() {
            case "template": modified = AnyView(view.symbolRenderingMode(.monochrome))
            default: modified = AnyView(view)
            }

        case "symbolRenderingMode":
            let mode = arguments.first.flatMap { SwiftUIConstants.caseName(from: $0) } ?? "monochrome"
            switch mode.lowercased() {
            case "multicolor": modified = AnyView(view.symbolRenderingMode(.multicolor))
            case "hierarchical": modified = AnyView(view.symbolRenderingMode(.hierarchical))
            case "palette": modified = AnyView(view.symbolRenderingMode(.palette))
            default: modified = AnyView(view.symbolRenderingMode(.monochrome))
            }

        // Lifecycle — closures handled by the bridge
        case "onAppear", "onDisappear", "onChange", "task":
            // These require closure wrapping, handled at a higher level
            modified = AnyView(view)

        // Interaction
        case "onTapGesture":
            modified = AnyView(view) // Closure handled at bridge level

        case "allowsHitTesting":
            let allow = arguments.first?.boolValue ?? true
            modified = AnyView(view.allowsHitTesting(allow))

        case "contentShape":
            modified = AnyView(view.contentShape(Rectangle()))

        // List styling
        case "listStyle":
            let style = arguments.first.flatMap { SwiftUIConstants.caseName(from: $0) } ?? "automatic"
            switch style.lowercased() {
            case "plain": modified = AnyView(view.listStyle(.plain))
            #if os(iOS)
            case "grouped": modified = AnyView(view.listStyle(.grouped))
            case "insetgrouped": modified = AnyView(view.listStyle(.insetGrouped))
            case "sidebar": modified = AnyView(view.listStyle(.sidebar))
            #endif
            default: modified = AnyView(view.listStyle(.automatic))
            }

        // Animation
        case "animation":
            let anim = parseAnimation(from: arguments)
            modified = AnyView(view.animation(anim, value: true))

        case "transition":
            let transition = parseTransition(from: arguments)
            modified = AnyView(view.transition(transition))

        case "contentTransition":
            let name = arguments.first.flatMap { SwiftUIConstants.caseName(from: $0) } ?? "identity"
            switch name.lowercased() {
            case "opacity": modified = AnyView(view.contentTransition(.opacity))
            case "interpolate": modified = AnyView(view.contentTransition(.interpolate))
            case "numerictext": modified = AnyView(view.contentTransition(.numericText()))
            default: modified = AnyView(view.contentTransition(.identity))
            }

        case "symbolEffect":
            let name = arguments.first.flatMap { SwiftUIConstants.caseName(from: $0) } ?? "bounce"
            switch name.lowercased() {
            case "pulse": modified = AnyView(view.symbolEffect(.pulse))
            case "variablecolor": modified = AnyView(view.symbolEffect(.variableColor))
            case "scale": modified = AnyView(view.symbolEffect(.scale.up))
            default: modified = AnyView(view.symbolEffect(.bounce))
            }

        // Color
        case "tint":
            if let arg = arguments.first, let color = Self.colorFromValue(arg) {
                modified = AnyView(view.tint(color))
            } else {
                modified = AnyView(view)
            }

        case "accentColor":
            if let arg = arguments.first, let color = Self.colorFromValue(arg) {
                modified = AnyView(view.tint(color)) // accentColor deprecated, use tint
            } else {
                modified = AnyView(view)
            }

        // Layout
        case "ignoresSafeArea":
            modified = AnyView(view.ignoresSafeArea())

        case "zIndex":
            let z = arguments.first?.doubleValue ?? 0
            modified = AnyView(view.zIndex(z))

        // Effects
        case "blur":
            let radius = arguments.first?.doubleValue ?? 3
            modified = AnyView(view.blur(radius: CGFloat(radius)))

        case "mask":
            modified = AnyView(view) // Requires shape argument — pass through

        default:
            // Unknown modifier — pass through unchanged
            modified = AnyView(view)
        }

        return (modified, descriptor)
    }

    // MARK: - Helpers

    private static func namedColor(_ name: String) -> Color? {
        SwiftUIConstants.color(named: name)
    }

    /// Extract a Color from a Value — supports both enum cases (.red) and strings ("red").
    static func colorFromValue(_ value: Value) -> Color? {
        if case .enumCase(let ref) = value, ref.typeName == "Color" {
            return namedColor(ref.caseName)
        }
        if let name = value.stringValue {
            return namedColor(name)
        }
        return nil
    }

    /// Extract a TextAlignment from a Value — supports both enum cases (.center) and strings ("center").
    static func textAlignmentFromValue(_ value: Value) -> TextAlignment {
        let name: String
        if case .enumCase(let ref) = value { name = ref.caseName }
        else { name = value.stringValue ?? "leading" }
        switch name {
        case "center": return .center
        case "trailing": return .trailing
        default: return .leading
        }
    }

    private static func systemFont(_ name: String) -> Font {
        SwiftUIConstants.font(named: name)
    }

    private static func edgeSet(from name: String) -> Edge.Set {
        switch name.lowercased() {
        case "top": return .top
        case "bottom": return .bottom
        case "leading": return .leading
        case "trailing": return .trailing
        case "horizontal": return .horizontal
        case "vertical": return .vertical
        case "all": return .all
        default: return .all
        }
    }

    /// Extract a dimension value — handles .infinity enum case and numeric values.
    private static func dimensionValue(from args: [Value], named name: String) -> CGFloat? {
        for arg in args {
            if case .enumCase(let ref) = arg, ref.caseName == "infinity" {
                // .infinity in a frame context → .infinity
                return .infinity
            }
        }
        // Try numeric argument (positional — named params not fully supported yet)
        return nil
    }

    private static func argumentDict(from args: [Value], for name: String) -> [String: Value] {
        var dict: [String: Value] = [:]
        for (i, arg) in args.enumerated() {
            dict["arg\(i)"] = arg
        }
        return dict
    }

    private static func argNamed(_ value: Value, _ name: String) -> Bool {
        return true
    }

    // MARK: - Animation Parsing

    /// Parse animation type from arguments.
    /// Accepts: "default", "easeIn", "easeOut", "easeInOut", "linear", "spring",
    /// or a duration as Double.
    public static func parseAnimation(from args: [Value]) -> Animation {
        guard let first = args.first else { return .default }

        // Accept both enum case (.easeIn) and string ("easeIn")
        if let name = SwiftUIConstants.caseName(from: first),
           let anim = SwiftUIConstants.animation(named: name) {
            return anim
        }

        // Duration as number: .animation(0.3) → .easeInOut(duration:)
        if let duration = first.doubleValue {
            return .easeInOut(duration: duration)
        }

        return .default
    }

    public static func parseTransition(from args: [Value]) -> AnyTransition {
        guard let first = args.first else { return .opacity }

        if let name = SwiftUIConstants.caseName(from: first),
           let transition = SwiftUIConstants.transition(named: name) {
            return transition
        }

        return .opacity
    }
}
#endif
