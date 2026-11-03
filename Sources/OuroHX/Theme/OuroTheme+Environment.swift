public import SwiftUI

/// A radius step, named as on web (`--radius-sm` … `--radius-4xl`). `xl2` is web's `2xl`.
public enum OuroRadius: String, CaseIterable, Sendable {
    case sm, md, lg, xl, xl2 = "2xl", xl3 = "3xl", xl4 = "4xl"

    /// The step's multiple of the theme's base radius, as in HX's CSS.
    public var scale: Double {
        switch self {
        case .sm: 0.6
        case .md: 0.8
        case .lg: 1
        case .xl: 1.4
        case .xl2: 1.8
        case .xl3: 2.2
        case .xl4: 2.6
        }
    }
}

extension OuroTheme {
    /// The radius of a step, in points: the base radius (`--radius`, 12 in Pearl) times the step's scale.
    public func radius(_ step: OuroRadius) -> Double { radius * step.scale }
}

/// A theme as it is seen: the theme, the colour scheme and the contrast setting, and the colours they give.
public struct OuroHXStyle: Sendable {
    public var theme: OuroTheme
    public var scheme: ColorScheme
    public var contrast: ColorSchemeContrast

    public init(theme: OuroTheme, scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) {
        self.theme = theme
        self.scheme = scheme
        self.contrast = contrast
    }

    /// The theme's colours for the scheme, raised by ``OuroColor/increasedContrast(_:)`` when contrast is increased.
    public var colors: OuroColors {
        let base = theme.colors(scheme)
        return contrast == .increased ? OuroColor.increasedContrast(base) : base
    }
}

extension EnvironmentValues {
    /// The Ouro HX theme in effect. Set it with `.ouroTheme(_:)`.
    @Entry public var ouroTheme: OuroTheme = OuroTokens.theme(OuroTokens.defaultTheme)
    /// The theme's colours for the current colour scheme and contrast. Set by `.ouroTheme(_:)`; without it, Pearl's
    /// light colours whatever the scheme, so theme the root.
    @Entry public var ouroColors: OuroColors = OuroTokens.theme(OuroTokens.defaultTheme).light
}

private struct OuroThemeModifier: ViewModifier {
    let theme: OuroTheme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let colors = OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast).colors
        content
            .environment(\.ouroTheme, theme)
            .environment(\.ouroColors, colors)
            .tint(colors.primary)
    }
}

extension View {
    /// Themes this view and its children: `ouroTheme` and `ouroColors` in the environment, following light, dark and
    /// Increase Contrast, and the theme's primary as the tint.
    public func ouroTheme(_ theme: OuroTheme) -> some View { modifier(OuroThemeModifier(theme: theme)) }

    /// Themes this view with one of HX's themes by name.
    public func ouroTheme(_ name: OuroThemeName) -> some View { ouroTheme(OuroTokens.theme(name)) }
}
