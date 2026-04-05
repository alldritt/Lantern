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
            if let value = arguments.first?.doubleValue {
                modified = AnyView(view.padding(CGFloat(value)))
            } else {
                modified = AnyView(view.padding())
            }

        case "frame":
            let width = arguments.first { argNamed($0, "width") }?.doubleValue.map { CGFloat($0) }
            let height = arguments.first { argNamed($0, "height") }?.doubleValue.map { CGFloat($0) }
            modified = AnyView(view.frame(width: width, height: height))

        case "fixedSize":
            modified = AnyView(view.fixedSize())

        case "offset":
            let x = arguments.first?.doubleValue ?? 0
            let y = arguments.count > 1 ? arguments[1].doubleValue ?? 0 : 0
            modified = AnyView(view.offset(x: CGFloat(x), y: CGFloat(y)))

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
            let alignment: TextAlignment = {
                switch arguments.first?.stringValue {
                case "center": return .center
                case "trailing": return .trailing
                default: return .leading
                }
            }()
            modified = AnyView(view.multilineTextAlignment(alignment))

        // Appearance
        case "foregroundColor", "foregroundStyle":
            if let colorName = arguments.first?.stringValue, let color = namedColor(colorName) {
                modified = AnyView(view.foregroundStyle(color))
            } else {
                modified = AnyView(view)
            }

        case "background":
            if let colorName = arguments.first?.stringValue, let color = namedColor(colorName) {
                modified = AnyView(view.background(color))
            } else {
                modified = AnyView(view)
            }

        case "overlay":
            if let colorName = arguments.first?.stringValue, let color = namedColor(colorName) {
                modified = AnyView(view.overlay(color))
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
            // Default to circle for now
            modified = AnyView(view.clipShape(Circle()))

        case "shadow":
            let radius = arguments.first?.doubleValue ?? 5
            modified = AnyView(view.shadow(radius: CGFloat(radius)))

        case "border":
            if let colorName = arguments.first?.stringValue, let color = namedColor(colorName) {
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
            let style = arguments.first?.stringValue ?? "automatic"
            switch style {
            case "plain": modified = AnyView(view.listStyle(.plain))
            #if os(iOS)
            case "grouped": modified = AnyView(view.listStyle(.grouped))
            case "insetGrouped": modified = AnyView(view.listStyle(.insetGrouped))
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
            let name = arguments.first?.stringValue ?? "identity"
            switch name.lowercased() {
            case "opacity": modified = AnyView(view.contentTransition(.opacity))
            case "interpolate": modified = AnyView(view.contentTransition(.interpolate))
            case "numerictext": modified = AnyView(view.contentTransition(.numericText()))
            case "identity": modified = AnyView(view.contentTransition(.identity))
            default: modified = AnyView(view.contentTransition(.identity))
            }

        case "symbolEffect":
            let name = arguments.first?.stringValue ?? "bounce"
            switch name.lowercased() {
            case "bounce": modified = AnyView(view.symbolEffect(.bounce))
            case "pulse": modified = AnyView(view.symbolEffect(.pulse))
            case "variablecolor": modified = AnyView(view.symbolEffect(.variableColor))
            case "scale": modified = AnyView(view.symbolEffect(.scale.up))
            default: modified = AnyView(view.symbolEffect(.bounce))
            }

        // Color
        case "tint":
            if let colorName = arguments.first?.stringValue, let color = namedColor(colorName) {
                modified = AnyView(view.tint(color))
            } else {
                modified = AnyView(view)
            }

        case "accentColor":
            if let colorName = arguments.first?.stringValue, let color = namedColor(colorName) {
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

    private static func systemFont(_ name: String) -> Font {
        switch name.lowercased() {
        case "largetitle": return .largeTitle
        case "title": return .title
        case "title2": return .title2
        case "title3": return .title3
        case "headline": return .headline
        case "subheadline": return .subheadline
        case "body": return .body
        case "callout": return .callout
        case "footnote": return .footnote
        case "caption": return .caption
        case "caption2": return .caption2
        default: return .body
        }
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

        if let name = first.stringValue {
            switch name.lowercased() {
            case "default": return .default
            case "easein": return .easeIn
            case "easeout": return .easeOut
            case "easeinout": return .easeInOut
            case "linear": return .linear
            case "spring": return .spring()
            case "bouncy": return .bouncy
            case "smooth": return .smooth
            case "snappy": return .snappy
            case "interactivespring": return .interactiveSpring()
            default: return .default
            }
        }

        // Duration as number: .animation(0.3) → .easeInOut(duration:)
        if let duration = first.doubleValue {
            return .easeInOut(duration: duration)
        }

        return .default
    }

    /// Parse transition type from arguments.
    /// Accepts: "opacity", "slide", "scale", "move", "push",
    /// "asymmetric", or combined.
    public static func parseTransition(from args: [Value]) -> AnyTransition {
        guard let first = args.first else { return .opacity }

        if let name = first.stringValue {
            switch name.lowercased() {
            case "opacity": return .opacity
            case "slide": return .slide
            case "scale": return .scale
            case "identity": return .identity
            case "moveleading": return .move(edge: .leading)
            case "movetrailing": return .move(edge: .trailing)
            case "movetop": return .move(edge: .top)
            case "movebottom": return .move(edge: .bottom)
            case "push": return .push(from: .trailing)
            default: return .opacity
            }
        }

        return .opacity
    }
}
#endif
