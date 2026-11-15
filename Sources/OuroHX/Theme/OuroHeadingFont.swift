public import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension OuroFont {
    /// The font a theme's headings resolve to: the first family in ``OuroTheme/heading`` (CSS `--font-heading`) that
    /// is a generic family or available to the app, as ``resolve(_:in:registered:)`` picks a type role's. A theme with
    /// no heading families resolves to the system font.
    public static func heading(
        _ theme: OuroTheme, registered: (String) -> Bool = OuroFont.isRegistered
    ) -> Resolution {
        resolve(families: theme.heading, registered: registered)
    }

    /// The default point size of a text style, which a custom face scales from with Dynamic Type.
    static func defaultSize(_ style: Font.TextStyle) -> Double {
        #if canImport(UIKit)
        let uiStyle: UIFont.TextStyle = switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
        let large = UITraitCollection(preferredContentSizeCategory: .large)
        return UIFont.preferredFont(forTextStyle: uiStyle, compatibleWith: large).pointSize
        #else
        let nsStyle: NSFont.TextStyle = switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
        return NSFont.preferredFont(forTextStyle: nsStyle).pointSize
        #endif
    }
}

extension Font {
    /// A heading in a theme's heading font (``OuroTheme/heading``, CSS `--font-heading`), at a text style's size and a
    /// CSS weight, scaled with Dynamic Type. Kit titles use it where web's use `--font-heading`: ``OuroEmptyState``,
    /// ``OuroPageHeader``, ``OuroCard`` and the sheet. In a theme whose heading is the system font (Pearl) it is
    /// `.system(style).weight(weight)`, so nothing changes there. Pass `registered` only in tests.
    public static func ouroHeading(
        _ style: Font.TextStyle, weight css: Int, in theme: OuroTheme,
        registered: (String) -> Bool = OuroFont.isRegistered
    ) -> Font {
        let weight = OuroFont.weight(css)
        switch OuroFont.heading(theme, registered: registered) {
        case .system(let design):
            return .system(style, design: design).weight(weight)
        case .custom(let family):
            let size = OuroFont.defaultSize(style)
            guard let face = OuroFont.face(family: family, weight: css) else {
                return .custom(family, size: size, relativeTo: style).weight(weight)
            }
            let font = Font.custom(face.postScriptName, size: size, relativeTo: style)
            return face.isVariable || !face.isExactWeight ? font.weight(weight) : font
        }
    }
}
