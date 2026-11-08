public import SwiftUI
import CoreText

/// A theme's text roles as fonts: the first family in the role's stack that the app has registered, as a browser picks
/// from a CSS `font-family` list, at the role's size, scaled with Dynamic Type relative to its text style. When no
/// family is registered, the system font in the design the stack's generic family asks for (`serif` gives New York).
public enum OuroFont {
    /// Which font a type role resolves to.
    public enum Resolution: Sendable, Equatable {
        /// A registered family, by its family name.
        case custom(String)
        /// The system font in a design.
        case system(design: Font.Design)
    }

    /// CSS generic families, which name a system design and are never looked up as a family.
    private static let generics: [String: Font.Design] = [
        "serif": .serif, "ui-serif": .serif,
        "sans-serif": .default, "ui-sans-serif": .default, "system-ui": .default, "-apple-system": .default,
        "monospace": .monospaced, "ui-monospace": .monospaced,
        "ui-rounded": .rounded,
    ]

    /// Whether a font family is available to the app: installed with the system or registered by the app (a bundled
    /// font in `UIAppFonts` or `ATSApplicationFontsPath`, or `CTFontManagerRegisterFontsForURL`). Asked live, so a font
    /// registered after launch counts.
    public static func isRegistered(_ family: String) -> Bool {
        // One family's descriptors, with the family as a mandatory attribute so Core Text answers nil rather than a
        // substitute: cheaper than listing every family (`CTFontManagerCopyAvailableFontFamilyNames`) on each render.
        let attributes = [kCTFontFamilyNameAttribute: family] as CFDictionary
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes)
        let mandatory = Set([kCTFontFamilyNameAttribute as String]) as CFSet
        return CTFontDescriptorCreateMatchingFontDescriptors(descriptor, mandatory) != nil
    }

    /// The font a type role resolves to in a theme's extras.
    public static func resolve(
        _ token: OuroTypeToken, in extras: OuroThemeExtras, registered: (String) -> Bool = OuroFont.isRegistered
    ) -> Resolution {
        let stack = extras.fonts[token.family] ?? []
        for family in stack {
            if let design = generics[family.lowercased()] { return .system(design: design) }
            if registered(family) { return .custom(family) }
        }
        return .system(design: .default)
    }

    /// A CSS weight (100 to 900) as SwiftUI's weight, rounding to the nearest hundred as CSS's fallback does.
    public static func weight(_ css: Int) -> Font.Weight {
        switch (min(max(css, 100), 900) + 50) / 100 * 100 {
        case 100: .ultraLight
        case 200: .thin
        case 300: .light
        case 400: .regular
        case 500: .medium
        case 600: .semibold
        case 700: .bold
        case 800: .heavy
        default: .black
        }
    }

    /// The role's letter spacing in points, at a Dynamic Type scale (1 at the default text size).
    public static func tracking(_ token: OuroTypeToken, scale: Double) -> Double { token.tracking * scale }

    /// The space SwiftUI adds between lines for the role's CSS line height, at a Dynamic Type scale.
    public static func lineSpacing(_ token: OuroTypeToken, scale: Double) -> Double {
        max(0, (token.lineHeight - 1) * token.size * scale)
    }
}

extension Font {
    /// A theme's text role as a font: see ``OuroFont``. Pass `registered` only in tests.
    public static func ouro(
        _ token: OuroTypeToken, in extras: OuroThemeExtras, registered: (String) -> Bool = OuroFont.isRegistered
    ) -> Font {
        let weight = OuroFont.weight(token.weight)
        switch OuroFont.resolve(token, in: extras, registered: registered) {
        case .custom(let family):
            return .custom(family, size: token.size, relativeTo: token.textStyle).weight(weight)
        case .system(let design):
            return .system(token.textStyle, design: design).weight(weight)
        }
    }
}

private struct OuroTypeModifier: ViewModifier {
    let token: OuroTypeToken
    let extras: OuroThemeExtras
    @ScaledMetric private var scale: Double

    init(token: OuroTypeToken, extras: OuroThemeExtras) {
        self.token = token
        self.extras = extras
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: token.textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(.ouro(token, in: extras))
            .tracking(OuroFont.tracking(token, scale: scale))
            .lineSpacing(OuroFont.lineSpacing(token, scale: scale))
    }
}

extension View {
    /// Sets a theme's text role on this view: its font, and its letter spacing and line height, both scaled with
    /// Dynamic Type so an eyebrow keeps its tracked look at every text size.
    public func ouroType(_ token: OuroTypeToken, in extras: OuroThemeExtras) -> some View {
        modifier(OuroTypeModifier(token: token, extras: extras))
    }

    /// Sets the theme in the environment's text role (see ``ouroTheme(_:)-(OuroTheme)``). A theme without the role
    /// leaves the view's font alone.
    public func ouroType(_ type: OuroExtraType) -> some View { modifier(OuroThemeTypeModifier(type: type)) }
}

private struct OuroThemeTypeModifier: ViewModifier {
    let type: OuroExtraType
    @Environment(\.ouroTheme) private var theme

    func body(content: Content) -> some View {
        if let token = theme.extras.type[type] {
            content.ouroType(token, in: theme.extras)
        } else {
            content
        }
    }
}
