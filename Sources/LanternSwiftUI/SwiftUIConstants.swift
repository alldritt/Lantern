#if canImport(SwiftUI)
import SwiftUI

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
        ("Edge", ["top", "bottom", "leading", "trailing"]),
        ("ContentMode", ["fit", "fill"]),
        ("Axis", ["horizontal", "vertical"]),
    ]
}
#endif
