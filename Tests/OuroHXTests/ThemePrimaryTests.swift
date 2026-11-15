@testable import OuroHX
import SwiftUI
import Testing

/// `withPrimary` changes the primary and what follows it, and nothing else, so an app can brand a theme without
/// copying its other colours (Gatefold copied all 44 to change six).
@Suite struct ThemePrimaryTests {
    static let follows: Set<String> = ["primary", "ring", "sidebarPrimary", "sidebarRing"]
    static let labels: Set<String> = ["primaryForeground", "sidebarPrimaryForeground"]
    static let ribbon = Color(red: 0x2F / 255, green: 0x5D / 255, blue: 0x8A / 255)
    static let night = Color(red: 0x7F / 255, green: 0xA6 / 255, blue: 0xD6 / 255)

    /// Every colour by name, read with `Mirror`, so a colour core adds is checked without editing this test.
    static func named(_ c: OuroColors) -> [String: Color.Resolved] {
        Dictionary(uniqueKeysWithValues: Mirror(reflecting: c).children.compactMap { child in
            (child.value as? Color).map { (child.label ?? "", $0.resolve(in: EnvironmentValues())) }
        })
    }

    @Test(arguments: OuroThemeName.allCases)
    func onlyThePrimaryAndWhatFollowsItChange(theme: OuroThemeName) throws {
        let base = OuroTokens.theme(theme)
        let branded = base.withPrimary(light: Self.ribbon, dark: Self.night, lightLabel: .white, darkLabel: .black)
        for (mode, before, after, fill, label) in [("light", base.light, branded.light, Self.ribbon, Color.white), ("dark", base.dark, branded.dark, Self.night, Color.black)] {
            let (old, new) = (Self.named(before), Self.named(after))
            #expect(old.count == 44 && Set(old.keys) == Set(new.keys), "\(mode): read \(old.count) colours")
            for (name, colour) in new {
                if Self.follows.contains(name) {
                    #expect(colour == fill.resolve(in: EnvironmentValues()), "\(theme) \(mode) \(name) is not the new primary")
                } else if Self.labels.contains(name) {
                    #expect(colour == label.resolve(in: EnvironmentValues()), "\(theme) \(mode) \(name) is not the new label")
                } else {
                    #expect(colour == old[name], "\(theme) \(mode) \(name) changed")
                }
            }
        }
        #expect(branded.name == base.name && branded.radius == base.radius && branded.heading == base.heading)
        #expect(branded.extras.light.count == base.extras.light.count && branded.extras.dark.count == base.extras.dark.count)
    }

    @Test func withoutALabelTheKitPicksTheOneThatReads() {
        let branded = OuroTokens.pearl.withPrimary(light: Self.ribbon, dark: Self.night)
        let env = EnvironmentValues()
        // White reads on the deep blue by day; ink on the light blue by night.
        #expect(branded.light.primaryForeground.resolve(in: env) == Color.white.resolve(in: env))
        #expect(branded.dark.primaryForeground.resolve(in: env) == OuroColor.ink.resolve(in: env))
        for c in [branded.light, branded.dark] {
            #expect(OuroColor.contrastRatio(c.primaryForeground.resolve(in: env), c.primary.resolve(in: env)) >= 4.5)
        }
    }
}
