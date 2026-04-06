#if canImport(SwiftUI)
import SwiftUI
import LanternVM

/// Centralized mappings from string names to SwiftUI values.
/// Used by both bridge registration (enum static properties) and
/// ModifierApplicator (value resolution). Single source of truth.
public enum SwiftUIConstants {

    // MARK: - Colors

    public static let colors: [(name: String, color: Color)] = [
        ("red", .red), ("blue", .blue), ("green", .green),
        ("yellow", .yellow), ("orange", .orange), ("purple", .purple),
        ("pink", .pink), ("white", .white), ("black", .black),
        ("gray", .gray), ("clear", .clear),
        ("primary", .primary), ("secondary", .secondary),
        ("brown", .brown), ("cyan", .cyan), ("indigo", .indigo),
        ("mint", .mint), ("teal", .teal),
    ]

    /// Also accept "grey" as alias for "gray", "accentColor" for accentColor.
    public static func color(named name: String) -> Color? {
        if name.lowercased() == "grey" { return .gray }
        if name.lowercased() == "accentcolor" { return .accentColor }
        return colors.first(where: { $0.name.lowercased() == name.lowercased() })?.color
    }

    public static let colorNames: [String] = colors.map(\.name) + ["grey", "accentColor"]

    // MARK: - Fonts

    public static let fonts: [(name: String, font: Font)] = [
        ("largeTitle", .largeTitle), ("title", .title),
        ("title2", .title2), ("title3", .title3),
        ("headline", .headline), ("subheadline", .subheadline),
        ("body", .body), ("callout", .callout),
        ("footnote", .footnote), ("caption", .caption),
        ("caption2", .caption2),
    ]

    public static func font(named name: String) -> Font {
        fonts.first(where: { $0.name.lowercased() == name.lowercased() })?.font ?? .body
    }

    public static let fontNames: [String] = fonts.map(\.name)

    // MARK: - Enum-Like Types for Bridge Registration

    // MARK: - Animations

    public static let animationNames = [
        "default", "easeIn", "easeOut", "easeInOut", "linear",
        "spring", "bouncy", "smooth", "snappy", "interactiveSpring",
    ]

    public static func animation(named name: String) -> Animation? {
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
        default: return nil
        }
    }

    // MARK: - Transitions

    public static let transitionNames = [
        "opacity", "slide", "scale", "identity",
        "moveLeading", "moveTrailing", "moveTop", "moveBottom",
        "push",
    ]

    public static func transition(named name: String) -> AnyTransition? {
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
        default: return nil
        }
    }

    // MARK: - Content Transitions

    public static let contentTransitionNames = [
        "opacity", "interpolate", "numericText", "identity",
    ]

    // MARK: - Symbol Effects

    public static let symbolEffectNames = [
        "bounce", "pulse", "variableColor", "scale",
    ]

    // MARK: - List Styles

    public static let listStyleNames = [
        "automatic", "plain", "grouped", "insetGrouped", "sidebar",
    ]

    // MARK: - Clip Shapes

    public static let clipShapeNames = [
        "circle", "capsule", "rectangle", "ellipse",
    ]

    // MARK: - Enum Type Registration

    /// All enum-like types with their case names, used for bridge static property registration.
    public static let enumTypes: [(typeName: String, caseNames: [String])] = [
        ("Font", fontNames),
        ("Color", colorNames),
        ("TextAlignment", ["leading", "center", "trailing"]),
        ("HorizontalAlignment", ["leading", "center", "trailing"]),
        ("VerticalAlignment", ["top", "center", "bottom", "firstTextBaseline", "lastTextBaseline"]),
        ("Alignment", ["topLeading", "top", "topTrailing",
                        "leading", "center", "trailing",
                        "bottomLeading", "bottom", "bottomTrailing"]),
        ("Edge", ["top", "bottom", "leading", "trailing",
                  "horizontal", "vertical", "all"]),
        ("ContentMode", ["fit", "fill"]),
        ("Axis", ["horizontal", "vertical"]),
        ("Image.Scale", ["small", "medium", "large"]),
        ("RenderingMode", ["original", "template"]),
        ("SymbolRenderingMode", ["monochrome", "multicolor", "hierarchical", "palette"]),
        ("Font.Weight", ["ultraLight", "thin", "light", "regular", "medium",
                         "semibold", "bold", "heavy", "black"]),
        ("Font.Design", ["default", "monospaced", "rounded", "serif"]),
        ("Text.Case", ["uppercase", "lowercase"]),
        ("Text.TruncationMode", ["head", "middle", "tail"]),
        ("Animation", animationNames),
        ("AnyTransition", transitionNames),
        ("ContentTransition", contentTransitionNames),
        ("SymbolEffect", symbolEffectNames),
        ("ListStyle", listStyleNames),
        ("ClipShape", clipShapeNames),
    ]

    /// Extract the case name from a Value that's either an enum case or a string.
    public static func caseName(from value: Value) -> String? {
        if case .enumCase(let ref) = value { return ref.caseName }
        return value.stringValue
    }
}
#endif
