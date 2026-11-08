public import SwiftUI
import CoreText
import os
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

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

    // MARK: Faces

    /// The face a family gives for a weight: its PostScript name, its Core Text weight (-1 to 1), and whether that
    /// weight is the one asked for. A variable font with a weight axis supplies every weight.
    public struct Face: Sendable, Equatable {
        public let postScriptName: String
        public let weight: Double
        public let isExactWeight: Bool
        public let isVariable: Bool
    }

    /// Core Text's weight trait for a CSS weight (Apple's `UIFont.Weight` values).
    static func coreTextWeight(_ css: Int) -> Double {
        switch (min(max(css, 100), 900) + 50) / 100 * 100 {
        case 100: -0.8
        case 200: -0.6
        case 300: -0.4
        case 400: 0
        case 500: 0.23
        case 600: 0.3
        case 700: 0.4
        case 800: 0.56
        default: 0.62
        }
    }

    /// The upright face of a family nearest a CSS weight, or nil when the family isn't registered. `isExactWeight` is
    /// false when the family has no face within a step of the weight, such as one regular file asked for 700.
    public static func face(family: String, weight css: Int) -> Face? {
        let attributes = [kCTFontFamilyNameAttribute: family] as CFDictionary
        let mandatory = Set([kCTFontFamilyNameAttribute as String]) as CFSet
        guard let matches = CTFontDescriptorCreateMatchingFontDescriptors(
            CTFontDescriptorCreateWithAttributes(attributes), mandatory) as? [CTFontDescriptor], !matches.isEmpty
        else { return nil }
        let wanted = coreTextWeight(css)
        var best: Face?
        var bestDistance = Double.infinity
        for descriptor in matches {
            let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [CFString: Any] ?? [:]
            let symbolic = (traits[kCTFontSymbolicTrait] as? NSNumber)?.uint32Value ?? 0
            if symbolic & CTFontSymbolicTraits.traitItalic.rawValue != 0 { continue }
            let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String ?? family
            let faceWeight = (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0
            let axes = CTFontCopyVariationAxes(CTFontCreateWithFontDescriptor(descriptor, 12, nil)) as? [[CFString: Any]] ?? []
            let variable = axes.contains { ($0[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.uint32Value == 0x7767_6874 }
            let distance = variable ? 0 : abs(faceWeight - wanted)
            if distance < bestDistance {
                bestDistance = distance
                // Within half the gap between neighbouring steps (semibold 0.3, bold 0.4) counts as the weight.
                best = Face(postScriptName: name, weight: variable ? wanted : faceWeight,
                            isExactWeight: distance <= 0.06, isVariable: variable)
            }
        }
        return best
    }

    /// Whether a family is registered with a face for every weight, for an app's test that its bundled fonts load:
    /// `#expect(OuroFont.isAvailable(family: "Fraunces", weights: [400, 600]))`.
    public static func isAvailable(family: String, weights: [Int]) -> Bool {
        weights.allSatisfy { face(family: family, weight: $0)?.isExactWeight == true }
    }

    // MARK: Line height

    /// The height of one line of the role's font at its default size (ascent, descent and leading), which SwiftUI
    /// lays out before adding `lineSpacing`.
    public static func naturalLineHeight(
        _ token: OuroTypeToken, in extras: OuroThemeExtras, registered: (String) -> Bool = OuroFont.isRegistered
    ) -> Double {
        let font: CTFont
        switch resolve(token, in: extras, registered: registered) {
        case .custom(let family):
            if let face = face(family: family, weight: token.weight) {
                font = CTFontCreateWithName(face.postScriptName as CFString, token.size, nil)
            } else {
                font = CTFontCreateWithName(family as CFString, token.size, nil)
            }
        case .system(let design):
            font = systemFont(size: token.size, weight: token.weight, design: design)
        }
        return Double(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }

    /// What SwiftUI's `lineSpacing` adds so a line is the role's CSS line height, at a Dynamic Type scale: the CSS line
    /// height less the font's own line, never negative.
    public static func lineSpacing(
        _ token: OuroTypeToken, in extras: OuroThemeExtras, scale: Double,
        registered: (String) -> Bool = OuroFont.isRegistered
    ) -> Double {
        max(0, (token.lineHeight * token.size - naturalLineHeight(token, in: extras, registered: registered)) * scale)
    }

    private static func systemFont(size: Double, weight css: Int, design: Font.Design) -> CTFont {
        #if canImport(UIKit)
        let base = UIFont.systemFont(ofSize: size, weight: UIFont.Weight(coreTextWeight(css)))
        let systemDesign: UIFontDescriptor.SystemDesign = switch design {
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        default: .default
        }
        let descriptor = base.fontDescriptor.withDesign(systemDesign) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: size) as CTFont
        #else
        let base = NSFont.systemFont(ofSize: size, weight: NSFont.Weight(coreTextWeight(css)))
        let systemDesign: NSFontDescriptor.SystemDesign = switch design {
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        default: .default
        }
        let descriptor = base.fontDescriptor.withDesign(systemDesign) ?? base.fontDescriptor
        return (NSFont(descriptor: descriptor, size: size) ?? base) as CTFont
        #endif
    }
}

extension Font {
    /// A theme's text role as a font: see ``OuroFont``. A registered family renders the face that has the role's
    /// weight, by PostScript name, so a missing weight never quietly renders regular: in a debug build it logs a fault
    /// naming the family and weight. This sets no tracking or line height; `.ouroType(_:)` sets all three. Pass
    /// `registered` only in tests.
    public static func ouro(
        _ token: OuroTypeToken, in extras: OuroThemeExtras, registered: (String) -> Bool = OuroFont.isRegistered
    ) -> Font {
        let weight = OuroFont.weight(token.weight)
        switch OuroFont.resolve(token, in: extras, registered: registered) {
        case .custom(let family):
            guard let face = OuroFont.face(family: family, weight: token.weight) else {
                return .custom(family, size: token.size, relativeTo: token.textStyle).weight(weight)
            }
            #if DEBUG
            if !face.isExactWeight {
                OuroFont.log.fault("OuroFont: \(family, privacy: .public) has no \(token.weight) face; bundle it. Using \(face.postScriptName, privacy: .public).")
            }
            #endif
            let font = Font.custom(face.postScriptName, size: token.size, relativeTo: token.textStyle)
            return face.isVariable ? font.weight(weight) : font
        case .system(let design):
            return .system(token.textStyle, design: design).weight(weight)
        }
    }
}

extension OuroFont {
    static let log = Logger(subsystem: "bot.ouro.hx", category: "font")
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
            .lineSpacing(OuroFont.lineSpacing(token, in: extras, scale: scale))
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
