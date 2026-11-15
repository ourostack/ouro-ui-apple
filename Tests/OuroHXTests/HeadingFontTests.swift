@testable import OuroHX
import SwiftUI
import Testing

/// Kit titles take the theme's heading font (CSS `--font-heading`), as web's Heading, Empty, PageHeader, Card and Sheet
/// titles do: the first family the app has, else the system design the stack's generic family names.
@Suite struct HeadingFontTests {
    private let none: (String) -> Bool = { _ in false }

    @Test func cookbookUsesItsSerifWhenTheAppRegistersIt() {
        #expect(OuroTokens.cookbook.heading.first == "Fraunces")
        #expect(OuroFont.heading(OuroTokens.cookbook, registered: { $0 == "Fraunces" }) == .custom("Fraunces"))
    }

    @Test func cookbookFallsBackThroughItsStackToTheSystemSerif() {
        #expect(OuroFont.heading(OuroTokens.cookbook, registered: { $0 == "Georgia" }) == .custom("Georgia"))
        #expect(OuroFont.heading(OuroTokens.cookbook, registered: none) == .system(design: .serif))
    }

    @Test func pearlHeadingsStayTheSystemFont() {
        // Pearl's stack starts -apple-system, BlinkMacSystemFont, SF Pro Display: all the system font.
        #expect(OuroFont.heading(OuroTokens.pearl, registered: { _ in true }) == .system(design: .default))
        #expect(Font.ouroHeading(.title2, weight: 700, in: OuroTokens.pearl) == Font.system(.title2, design: .default).weight(.bold))
    }

    @Test func genericFamiliesNameSystemDesigns() {
        #expect(OuroFont.heading(OuroTokens.coral, registered: none) == .system(design: .rounded))
        #expect(OuroFont.heading(OuroTokens.abyss, registered: none) == .system(design: .default))
        let bare = OuroTheme(name: .pearl, light: OuroTokens.pearl.light, dark: OuroTokens.pearl.dark, radius: OuroTokens.pearl.radius)
        #expect(bare.heading.isEmpty)
        #expect(OuroFont.heading(bare, registered: { _ in true }) == .system(design: .default))
    }

    @Test func pageHeaderTitleFollowsTheTheme() {
        #expect(OuroPageHeaderMetrics.titleFont(size: .md, level: 1) == OuroPageHeaderMetrics.titleFont(size: .md, level: 1, in: OuroTokens.pearl))
        #expect(OuroPageHeaderMetrics.titleFont(size: .lg, level: 1, in: OuroTokens.pearl) == Font.system(.largeTitle, design: .default).weight(.bold))
    }
}
