public import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Colour helpers: WCAG contrast, a readable label for any fill, increased-contrast colours, and colours that adapt
/// to light, dark and Increase Contrast by themselves.
public enum OuroColor {
    /// HX's ink, #1d1d1f: the dark label `readableLabel(on:)` picks on light fills.
    public static let ink = Color(.sRGB, red: 0.1137, green: 0.1137, blue: 0.1216)

    // MARK: Contrast

    /// WCAG 2 relative luminance, from 0 (black) to 1 (white). Opacity is ignored.
    public static func luminance(_ color: Color) -> Double { luminance(resolve(color)) }

    public static func luminance(_ c: Color.Resolved) -> Double {
        0.2126 * Double(c.linearRed) + 0.7152 * Double(c.linearGreen) + 0.0722 * Double(c.linearBlue)
    }

    /// WCAG 2 contrast between two colours, from 1 to 21. Text needs 4.5 (AA) or 7 (AAA); lines and icons need 3.
    public static func contrastRatio(_ a: Color, _ b: Color) -> Double { contrastRatio(resolve(a), resolve(b)) }

    public static func contrastRatio(_ a: Color.Resolved, _ b: Color.Resolved) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// White or ``ink``, whichever reads better on `fill`.
    public static func readableLabel(on fill: Color) -> Color {
        contrastRatio(.white, fill) >= contrastRatio(ink, fill) ? .white : ink
    }

    // MARK: Increased contrast

    /// The contrast ``increasedContrast(_:)`` raises text to.
    public static let increasedTextContrast = 7.0
    /// The contrast ``increasedContrast(_:)`` raises borders, inputs and focus rings to.
    public static let increasedLineContrast = 3.0

    /// The colours for Increase Contrast. Core v0.1.0 has no high-contrast tokens yet, so they are derived: each text
    /// colour moves toward black or white until it reaches 7:1 on its surface (WCAG AAA), and each line until 3:1. A
    /// surface moves only when its text cannot get there alone. Pairs that already pass are left alone.
    public static func increasedContrast(_ c: OuroColors) -> OuroColors {
        var v = Palette(c)
        let text: [(WritableKeyPath<Palette, Color.Resolved>, WritableKeyPath<Palette, Color.Resolved>)] = [
            (\.cardForeground, \.card), (\.popoverForeground, \.popover), (\.primaryForeground, \.primary),
            (\.secondaryForeground, \.secondary), (\.accentForeground, \.accent),
            (\.destructiveForeground, \.destructive), (\.successForeground, \.success),
            (\.warningForeground, \.warning), (\.sidebarForeground, \.sidebar),
            (\.sidebarPrimaryForeground, \.sidebarPrimary), (\.sidebarAccentForeground, \.sidebarAccent),
            (\.foreground, \.background),
        ]
        for (fg, bg) in text { separate(&v, fg, bg, increasedTextContrast) }
        // Muted text sits on muted fills and on the page: it must pass on both.
        separate(&v, \.mutedForeground, \.muted, increasedTextContrast)
        v.mutedForeground = push(v.mutedForeground, against: v.background, to: increasedTextContrast, alsoAgainst: v.muted)
        for line in [\Palette.border, \.input, \.ring] { v[keyPath: line] = push(v[keyPath: line], against: v.background, to: increasedLineContrast) }
        for line in [\Palette.sidebarBorder, \.sidebarRing] { v[keyPath: line] = push(v[keyPath: line], against: v.sidebar, to: increasedLineContrast) }
        return v.colors
    }

    // MARK: Adaptive colours

    /// A colour that follows light, dark and Increase Contrast by itself, without `.ouroTheme(_:)`. From Gatefold's
    /// `Color(light:dark:highContrastLight:highContrastDark:)`. Main actor: AppKit and UIKit colours resolve there.
    @MainActor
    public static func dynamic(light: Color, dark: Color, increasedLight: Color? = nil, increasedDark: Color? = nil) -> Color {
        let (l, d) = (platform(light), platform(dark))
        let (hl, hd) = (increasedLight.map(platform) ?? l, increasedDark.map(platform) ?? d)
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            return traits.userInterfaceStyle == .dark ? (high ? hd : d) : (high ? hl : l)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
            case .darkAqua?: d
            case .accessibilityHighContrastAqua?: hl
            case .accessibilityHighContrastDarkAqua?: hd
            default: l
            }
        })
        #else
        return light
        #endif
    }

    /// A theme's colours as adaptive colours: each follows light, dark and Increase Contrast by itself, for places the
    /// environment does not reach (UIKit and AppKit views, widgets, a snippet).
    @MainActor
    public static func dynamic(_ theme: OuroTheme) -> OuroColors {
        let (light, dark) = (Palette(theme.light), Palette(theme.dark))
        let (hl, hd) = (Palette(increasedContrast(theme.light)), Palette(increasedContrast(theme.dark)))
        return Palette.zip(light, dark, hl, hd) { l, d, il, id in
            dynamic(light: Color(l), dark: Color(d), increasedLight: Color(il), increasedDark: Color(id))
        }
    }

    // MARK: Internals

    static func resolve(_ color: Color) -> Color.Resolved { color.resolve(in: EnvironmentValues()) }

    #if canImport(UIKit)
    static func platform(_ color: Color) -> UIColor { UIColor(color) }
    #elseif canImport(AppKit)
    static func platform(_ color: Color) -> NSColor { NSColor(color) }
    #else
    static func platform(_ color: Color) -> Color { color }
    #endif

    static let black = Color.Resolved(red: 0, green: 0, blue: 0)
    static let white = Color.Resolved(red: 1, green: 1, blue: 1)

    /// `a` mixed toward `b` by `t`, in gamma-encoded sRGB.
    static func mix(_ a: Color.Resolved, _ b: Color.Resolved, _ t: Double) -> Color.Resolved {
        let t = Float(min(1, max(0, t)))
        return Color.Resolved(colorSpace: .sRGB, red: a.red + (b.red - a.red) * t, green: a.green + (b.green - a.green) * t, blue: a.blue + (b.blue - a.blue) * t, opacity: a.opacity)
    }

    /// The least mix of `color` toward black or white (whichever gains more; on a mid-tone surface that can flip a
    /// colour's polarity, which the theme tests would show) that reaches `target` against `surface`
    /// (and `other`, when given), or the extreme when nothing less does.
    static func push(_ color: Color.Resolved, against surface: Color.Resolved, to target: Double, alsoAgainst other: Color.Resolved? = nil) -> Color.Resolved {
        func worst(_ c: Color.Resolved) -> Double { min(contrastRatio(c, surface), other.map { contrastRatio(c, $0) } ?? .infinity) }
        guard worst(color) < target else { return color }
        let toward = worst(white) >= worst(black) ? white : black
        guard worst(toward) >= target else { return toward }
        var (lo, hi) = (0.0, 1.0)
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if worst(mix(color, toward, mid)) >= target { hi = mid } else { lo = mid }
        }
        return mix(color, toward, hi)
    }

    /// Raises a text and surface pair to `target`: the text first, then the surface away from it.
    static func separate(_ v: inout Palette, _ fg: WritableKeyPath<Palette, Color.Resolved>, _ bg: WritableKeyPath<Palette, Color.Resolved>, _ target: Double) {
        v[keyPath: fg] = push(v[keyPath: fg], against: v[keyPath: bg], to: target)
        if contrastRatio(v[keyPath: fg], v[keyPath: bg]) < target {
            v[keyPath: bg] = push(v[keyPath: bg], against: v[keyPath: fg], to: target)
        }
    }
}
