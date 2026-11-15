public import SwiftUI

extension OuroColors {
    /// These colours with another primary: `primary`, `ring`, `sidebarPrimary` and `sidebarRing` become `fill`, and
    /// `primaryForeground` and `sidebarPrimaryForeground` become `label`. Everything else is unchanged.
    ///
    /// - Parameters:
    ///   - fill: the brand colour the kit fills buttons, focus rings and selections with.
    ///   - label: text and symbols on that fill. Nil picks white or ink, whichever reads better on it
    ///     (``OuroColor/readableLabel(on:)``).
    public func withPrimary(_ fill: Color, label: Color? = nil) -> OuroColors {
        let label = label ?? OuroColor.readableLabel(on: fill)
        return OuroColors(
            background: background,
            foreground: foreground,
            card: card,
            cardForeground: cardForeground,
            popover: popover,
            popoverForeground: popoverForeground,
            primary: fill,
            primaryForeground: label,
            secondary: secondary,
            secondaryForeground: secondaryForeground,
            muted: muted,
            mutedForeground: mutedForeground,
            accent: accent,
            accentForeground: accentForeground,
            destructive: destructive,
            destructiveForeground: destructiveForeground,
            border: border,
            input: input,
            ring: fill,
            success: success,
            successForeground: successForeground,
            warning: warning,
            warningForeground: warningForeground,
            chart1: chart1,
            chart2: chart2,
            chart3: chart3,
            chart4: chart4,
            chart5: chart5,
            avatar1: avatar1,
            avatar2: avatar2,
            avatar3: avatar3,
            avatar4: avatar4,
            avatar5: avatar5,
            avatar6: avatar6,
            avatar7: avatar7,
            avatar8: avatar8,
            sidebar: sidebar,
            sidebarForeground: sidebarForeground,
            sidebarPrimary: fill,
            sidebarPrimaryForeground: label,
            sidebarAccent: sidebarAccent,
            sidebarAccentForeground: sidebarAccentForeground,
            sidebarBorder: sidebarBorder,
            sidebarRing: fill
        )
    }
}

extension OuroTheme {
    /// This theme in an app's brand colour: its primary (and the rings and sidebar colours that follow it) replaced in
    /// light and dark mode, and everything else, its name, radius, extras and heading included, kept.
    ///
    /// ```swift
    /// // Gatefold's ribbon: #2F5D8A by day, #7FA6D6 by night.
    /// static let gatefold = OuroTokens.pearl.withPrimary(
    ///     light: Color(red: 0x2F / 255, green: 0x5D / 255, blue: 0x8A / 255),
    ///     dark: Color(red: 0x7F / 255, green: 0xA6 / 255, blue: 0xD6 / 255))
    /// ```
    ///
    /// - Parameters:
    ///   - light: the primary in light mode.
    ///   - dark: the primary in dark mode.
    ///   - lightLabel: text on `light`; nil picks white or ink, whichever reads better.
    ///   - darkLabel: text on `dark`; nil picks white or ink, whichever reads better.
    public func withPrimary(light: Color, dark: Color, lightLabel: Color? = nil, darkLabel: Color? = nil) -> OuroTheme {
        OuroTheme(name: name, light: self.light.withPrimary(light, label: lightLabel),
                  dark: self.dark.withPrimary(dark, label: darkLabel), radius: radius, extras: extras, heading: heading)
    }
}
