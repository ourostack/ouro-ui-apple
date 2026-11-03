import SwiftUI

/// `OuroColors` with each colour resolved, so helpers can change one and build the struct back. Generated from the
/// vendored token file's field list; a token bump that adds a colour adds it here (the compiler says where).
struct Palette {
    var background: Color.Resolved
    var foreground: Color.Resolved
    var card: Color.Resolved
    var cardForeground: Color.Resolved
    var popover: Color.Resolved
    var popoverForeground: Color.Resolved
    var primary: Color.Resolved
    var primaryForeground: Color.Resolved
    var secondary: Color.Resolved
    var secondaryForeground: Color.Resolved
    var muted: Color.Resolved
    var mutedForeground: Color.Resolved
    var accent: Color.Resolved
    var accentForeground: Color.Resolved
    var destructive: Color.Resolved
    var destructiveForeground: Color.Resolved
    var border: Color.Resolved
    var input: Color.Resolved
    var ring: Color.Resolved
    var success: Color.Resolved
    var successForeground: Color.Resolved
    var warning: Color.Resolved
    var warningForeground: Color.Resolved
    var chart1: Color.Resolved
    var chart2: Color.Resolved
    var chart3: Color.Resolved
    var chart4: Color.Resolved
    var chart5: Color.Resolved
    var avatar1: Color.Resolved
    var avatar2: Color.Resolved
    var avatar3: Color.Resolved
    var avatar4: Color.Resolved
    var avatar5: Color.Resolved
    var avatar6: Color.Resolved
    var avatar7: Color.Resolved
    var avatar8: Color.Resolved
    var sidebar: Color.Resolved
    var sidebarForeground: Color.Resolved
    var sidebarPrimary: Color.Resolved
    var sidebarPrimaryForeground: Color.Resolved
    var sidebarAccent: Color.Resolved
    var sidebarAccentForeground: Color.Resolved
    var sidebarBorder: Color.Resolved
    var sidebarRing: Color.Resolved

    init(_ c: OuroColors) {
        background = OuroColor.resolve(c.background)
        foreground = OuroColor.resolve(c.foreground)
        card = OuroColor.resolve(c.card)
        cardForeground = OuroColor.resolve(c.cardForeground)
        popover = OuroColor.resolve(c.popover)
        popoverForeground = OuroColor.resolve(c.popoverForeground)
        primary = OuroColor.resolve(c.primary)
        primaryForeground = OuroColor.resolve(c.primaryForeground)
        secondary = OuroColor.resolve(c.secondary)
        secondaryForeground = OuroColor.resolve(c.secondaryForeground)
        muted = OuroColor.resolve(c.muted)
        mutedForeground = OuroColor.resolve(c.mutedForeground)
        accent = OuroColor.resolve(c.accent)
        accentForeground = OuroColor.resolve(c.accentForeground)
        destructive = OuroColor.resolve(c.destructive)
        destructiveForeground = OuroColor.resolve(c.destructiveForeground)
        border = OuroColor.resolve(c.border)
        input = OuroColor.resolve(c.input)
        ring = OuroColor.resolve(c.ring)
        success = OuroColor.resolve(c.success)
        successForeground = OuroColor.resolve(c.successForeground)
        warning = OuroColor.resolve(c.warning)
        warningForeground = OuroColor.resolve(c.warningForeground)
        chart1 = OuroColor.resolve(c.chart1)
        chart2 = OuroColor.resolve(c.chart2)
        chart3 = OuroColor.resolve(c.chart3)
        chart4 = OuroColor.resolve(c.chart4)
        chart5 = OuroColor.resolve(c.chart5)
        avatar1 = OuroColor.resolve(c.avatar1)
        avatar2 = OuroColor.resolve(c.avatar2)
        avatar3 = OuroColor.resolve(c.avatar3)
        avatar4 = OuroColor.resolve(c.avatar4)
        avatar5 = OuroColor.resolve(c.avatar5)
        avatar6 = OuroColor.resolve(c.avatar6)
        avatar7 = OuroColor.resolve(c.avatar7)
        avatar8 = OuroColor.resolve(c.avatar8)
        sidebar = OuroColor.resolve(c.sidebar)
        sidebarForeground = OuroColor.resolve(c.sidebarForeground)
        sidebarPrimary = OuroColor.resolve(c.sidebarPrimary)
        sidebarPrimaryForeground = OuroColor.resolve(c.sidebarPrimaryForeground)
        sidebarAccent = OuroColor.resolve(c.sidebarAccent)
        sidebarAccentForeground = OuroColor.resolve(c.sidebarAccentForeground)
        sidebarBorder = OuroColor.resolve(c.sidebarBorder)
        sidebarRing = OuroColor.resolve(c.sidebarRing)
    }

    var colors: OuroColors {
        OuroColors(
            background: Color(background),
            foreground: Color(foreground),
            card: Color(card),
            cardForeground: Color(cardForeground),
            popover: Color(popover),
            popoverForeground: Color(popoverForeground),
            primary: Color(primary),
            primaryForeground: Color(primaryForeground),
            secondary: Color(secondary),
            secondaryForeground: Color(secondaryForeground),
            muted: Color(muted),
            mutedForeground: Color(mutedForeground),
            accent: Color(accent),
            accentForeground: Color(accentForeground),
            destructive: Color(destructive),
            destructiveForeground: Color(destructiveForeground),
            border: Color(border),
            input: Color(input),
            ring: Color(ring),
            success: Color(success),
            successForeground: Color(successForeground),
            warning: Color(warning),
            warningForeground: Color(warningForeground),
            chart1: Color(chart1),
            chart2: Color(chart2),
            chart3: Color(chart3),
            chart4: Color(chart4),
            chart5: Color(chart5),
            avatar1: Color(avatar1),
            avatar2: Color(avatar2),
            avatar3: Color(avatar3),
            avatar4: Color(avatar4),
            avatar5: Color(avatar5),
            avatar6: Color(avatar6),
            avatar7: Color(avatar7),
            avatar8: Color(avatar8),
            sidebar: Color(sidebar),
            sidebarForeground: Color(sidebarForeground),
            sidebarPrimary: Color(sidebarPrimary),
            sidebarPrimaryForeground: Color(sidebarPrimaryForeground),
            sidebarAccent: Color(sidebarAccent),
            sidebarAccentForeground: Color(sidebarAccentForeground),
            sidebarBorder: Color(sidebarBorder),
            sidebarRing: Color(sidebarRing)
        )
    }

    /// Builds an `OuroColors` from four palettes, field by field.
    static func zip(_ a: Palette, _ b: Palette, _ c: Palette, _ d: Palette, _ make: (Color.Resolved, Color.Resolved, Color.Resolved, Color.Resolved) -> Color) -> OuroColors {
        OuroColors(
            background: make(a.background, b.background, c.background, d.background),
            foreground: make(a.foreground, b.foreground, c.foreground, d.foreground),
            card: make(a.card, b.card, c.card, d.card),
            cardForeground: make(a.cardForeground, b.cardForeground, c.cardForeground, d.cardForeground),
            popover: make(a.popover, b.popover, c.popover, d.popover),
            popoverForeground: make(a.popoverForeground, b.popoverForeground, c.popoverForeground, d.popoverForeground),
            primary: make(a.primary, b.primary, c.primary, d.primary),
            primaryForeground: make(a.primaryForeground, b.primaryForeground, c.primaryForeground, d.primaryForeground),
            secondary: make(a.secondary, b.secondary, c.secondary, d.secondary),
            secondaryForeground: make(a.secondaryForeground, b.secondaryForeground, c.secondaryForeground, d.secondaryForeground),
            muted: make(a.muted, b.muted, c.muted, d.muted),
            mutedForeground: make(a.mutedForeground, b.mutedForeground, c.mutedForeground, d.mutedForeground),
            accent: make(a.accent, b.accent, c.accent, d.accent),
            accentForeground: make(a.accentForeground, b.accentForeground, c.accentForeground, d.accentForeground),
            destructive: make(a.destructive, b.destructive, c.destructive, d.destructive),
            destructiveForeground: make(a.destructiveForeground, b.destructiveForeground, c.destructiveForeground, d.destructiveForeground),
            border: make(a.border, b.border, c.border, d.border),
            input: make(a.input, b.input, c.input, d.input),
            ring: make(a.ring, b.ring, c.ring, d.ring),
            success: make(a.success, b.success, c.success, d.success),
            successForeground: make(a.successForeground, b.successForeground, c.successForeground, d.successForeground),
            warning: make(a.warning, b.warning, c.warning, d.warning),
            warningForeground: make(a.warningForeground, b.warningForeground, c.warningForeground, d.warningForeground),
            chart1: make(a.chart1, b.chart1, c.chart1, d.chart1),
            chart2: make(a.chart2, b.chart2, c.chart2, d.chart2),
            chart3: make(a.chart3, b.chart3, c.chart3, d.chart3),
            chart4: make(a.chart4, b.chart4, c.chart4, d.chart4),
            chart5: make(a.chart5, b.chart5, c.chart5, d.chart5),
            avatar1: make(a.avatar1, b.avatar1, c.avatar1, d.avatar1),
            avatar2: make(a.avatar2, b.avatar2, c.avatar2, d.avatar2),
            avatar3: make(a.avatar3, b.avatar3, c.avatar3, d.avatar3),
            avatar4: make(a.avatar4, b.avatar4, c.avatar4, d.avatar4),
            avatar5: make(a.avatar5, b.avatar5, c.avatar5, d.avatar5),
            avatar6: make(a.avatar6, b.avatar6, c.avatar6, d.avatar6),
            avatar7: make(a.avatar7, b.avatar7, c.avatar7, d.avatar7),
            avatar8: make(a.avatar8, b.avatar8, c.avatar8, d.avatar8),
            sidebar: make(a.sidebar, b.sidebar, c.sidebar, d.sidebar),
            sidebarForeground: make(a.sidebarForeground, b.sidebarForeground, c.sidebarForeground, d.sidebarForeground),
            sidebarPrimary: make(a.sidebarPrimary, b.sidebarPrimary, c.sidebarPrimary, d.sidebarPrimary),
            sidebarPrimaryForeground: make(a.sidebarPrimaryForeground, b.sidebarPrimaryForeground, c.sidebarPrimaryForeground, d.sidebarPrimaryForeground),
            sidebarAccent: make(a.sidebarAccent, b.sidebarAccent, c.sidebarAccent, d.sidebarAccent),
            sidebarAccentForeground: make(a.sidebarAccentForeground, b.sidebarAccentForeground, c.sidebarAccentForeground, d.sidebarAccentForeground),
            sidebarBorder: make(a.sidebarBorder, b.sidebarBorder, c.sidebarBorder, d.sidebarBorder),
            sidebarRing: make(a.sidebarRing, b.sidebarRing, c.sidebarRing, d.sidebarRing)
        )
    }
}
