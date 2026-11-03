import OuroHX
import SwiftUI
import Testing

private func resolved(_ color: Color) -> Color.Resolved { color.resolve(in: EnvironmentValues()) }

/// Every foreground-on-background pair HX's CSS pairs, plus lines against their surface.
private var textPairs: [(String, KeyPath<OuroColors, Color>, KeyPath<OuroColors, Color>)] { [
    ("foreground", \.foreground, \.background), ("cardForeground", \.cardForeground, \.card),
    ("popoverForeground", \.popoverForeground, \.popover), ("primaryForeground", \.primaryForeground, \.primary),
    ("secondaryForeground", \.secondaryForeground, \.secondary), ("mutedForeground", \.mutedForeground, \.muted),
    ("mutedForeground on background", \.mutedForeground, \.background), ("accentForeground", \.accentForeground, \.accent),
    ("destructiveForeground", \.destructiveForeground, \.destructive), ("successForeground", \.successForeground, \.success),
    ("warningForeground", \.warningForeground, \.warning), ("sidebarForeground", \.sidebarForeground, \.sidebar),
    ("sidebarPrimaryForeground", \.sidebarPrimaryForeground, \.sidebarPrimary),
    ("sidebarAccentForeground", \.sidebarAccentForeground, \.sidebarAccent),
] }
private var linePairs: [(String, KeyPath<OuroColors, Color>, KeyPath<OuroColors, Color>)] { [
    ("border", \.border, \.background), ("input", \.input, \.background), ("ring", \.ring, \.background),
    ("sidebarBorder", \.sidebarBorder, \.sidebar), ("sidebarRing", \.sidebarRing, \.sidebar),
] }

@Suite struct ColorTests {
    @Test func contrastIsWCAG2() {
        #expect(abs(OuroColor.contrastRatio(.white, .black) - 21) < 0.01)
        #expect(abs(OuroColor.contrastRatio(.white, .white) - 1) < 0.001)
        // #0066cc on white: 5.57:1 (WebAIM).
        let blue = Color(.sRGB, red: 0, green: 0.4, blue: 0.8)
        #expect(abs(OuroColor.contrastRatio(blue, .white) - 5.57) < 0.02)
    }

    @Test func readableLabelPicksTheStrongerOfInkAndWhite() {
        #expect(resolved(OuroColor.readableLabel(on: Color(.sRGB, red: 0, green: 0.4, blue: 0.8))) == resolved(.white))
        #expect(resolved(OuroColor.readableLabel(on: Color(.sRGB, red: 1, green: 0.85, blue: 0.3))) == resolved(OuroColor.ink))
    }

    @Test(arguments: OuroThemeName.allCases, [ColorScheme.light, .dark])
    func increasedContrastReachesSevenToOneForTextAndThreeForLines(name: OuroThemeName, scheme: ColorScheme) {
        let colors = OuroColor.increasedContrast(OuroTokens.theme(name).colors(scheme))
        for (label, fg, bg) in textPairs {
            #expect(OuroColor.contrastRatio(colors[keyPath: fg], colors[keyPath: bg]) >= 7, "\(name) \(scheme) \(label)")
        }
        for (label, fg, bg) in linePairs {
            #expect(OuroColor.contrastRatio(colors[keyPath: fg], colors[keyPath: bg]) >= 3, "\(name) \(scheme) \(label)")
        }
    }

    @Test func increasedContrastLeavesPassingPairsAlone() {
        let pearl = OuroTokens.pearl.light
        let raised = OuroColor.increasedContrast(pearl)
        // #1d1d1f on white is already over 7:1.
        #expect(resolved(raised.foreground) == resolved(pearl.foreground))
        #expect(resolved(raised.background) == resolved(pearl.background))
    }
}

@Suite struct ThemeTests {
    @Test func radiiFollowWebsScale() {
        let pearl = OuroTokens.pearl
        #expect(pearl.radius == 12)
        #expect(abs(pearl.radius(.sm) - 7.2) < 1e-9)
        #expect(abs(pearl.radius(.md) - 9.6) < 1e-9)
        #expect(pearl.radius(.lg) == 12)
        #expect(abs(pearl.radius(.xl) - 16.8) < 1e-9)
        #expect(abs(pearl.radius(.xl2) - 21.6) < 1e-9)
        #expect(abs(pearl.radius(.xl3) - 26.4) < 1e-9)
        #expect(abs(pearl.radius(.xl4) - 31.2) < 1e-9)
    }

    @Test func colorsFollowSchemeAndContrast() {
        let abyss = OuroTokens.abyss
        #expect(resolved(OuroHXStyle(theme: abyss, scheme: .dark, contrast: .standard).colors.background) == resolved(abyss.dark.background))
        #expect(resolved(OuroHXStyle(theme: abyss, scheme: .light, contrast: .standard).colors.primary) == resolved(abyss.light.primary))
        let high = OuroHXStyle(theme: abyss, scheme: .light, contrast: .increased).colors
        #expect(OuroColor.contrastRatio(high.mutedForeground, high.background) >= 7)
    }

    @Test @MainActor func theModifierPutsTheThemeInTheEnvironment() {
        var seen: (OuroThemeName, Color.Resolved)?
        let view = Probe { env in seen = (env.ouroTheme.name, resolved(env.ouroColors.background)) }
            .ouroTheme(.abyss)
            .environment(\.colorScheme, .dark)
        _ = ImageRenderer(content: view).cgImage
        #expect(seen?.0 == .abyss)
        #expect(seen?.1 == resolved(OuroTokens.abyss.dark.background))
    }
}

/// Calls `read` with the environment it renders in.
struct Probe: View {
    @Environment(\.self) private var environment
    let read: (EnvironmentValues) -> Void
    var body: some View {
        read(environment)
        return Color.clear.frame(width: 1, height: 1)
    }
}

@Suite struct DynamicColorTests {
    @Test @MainActor func dynamicColorsFollowTheEnvironmentsScheme() {
        let colors = OuroColor.dynamic(OuroTokens.abyss)
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        var light = EnvironmentValues()
        light.colorScheme = .light
        // Through NSColor or UIColor and back, a channel can move by a rounding step, so compare by contrast.
        #expect(OuroColor.contrastRatio(colors.background.resolve(in: dark), OuroTokens.abyss.dark.background.resolve(in: dark)) < 1.01, "\(colors.background.resolve(in: dark))")
        #expect(OuroColor.contrastRatio(colors.background.resolve(in: light), OuroTokens.abyss.light.background.resolve(in: light)) < 1.01, "\(colors.background.resolve(in: light)) vs \(OuroTokens.abyss.light.background.resolve(in: light))")
    }
}
