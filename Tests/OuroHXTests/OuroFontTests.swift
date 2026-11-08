import OuroHX
import SwiftUI
import Testing

@Suite struct OuroFontTests {
    private let cookbook = OuroTokens.theme(.cookbook).extras
    private func token(_ type: OuroExtraType) throws -> OuroTypeToken { try #require(cookbook.type[type]) }

    @Test func fontFallsBackWhenNothingRegistered() throws {
        let display = try token(.sjTypeDisplay)
        #expect(OuroFont.resolve(display, in: cookbook, registered: { _ in false }) == .system(design: .serif))
        #expect(Font.ouro(display, in: cookbook, registered: { _ in false })
            == .system(display.textStyle, design: .serif).weight(.semibold))
    }

    @Test func fontUsesFirstRegisteredFamily() throws {
        let ui = try token(.sjTypeUi)
        // Plex is bundled by the app; with it missing, the next family in web's stack wins, as in a browser.
        #expect(OuroFont.resolve(ui, in: cookbook, registered: { $0 == "IBM Plex Sans Condensed" }) == .custom("IBM Plex Sans Condensed"))
        #expect(OuroFont.resolve(ui, in: cookbook, registered: { $0 == "Avenir Next Condensed" }) == .custom("Avenir Next Condensed"))
        #expect(Font.ouro(ui, in: cookbook, registered: { _ in true })
            == .custom("IBM Plex Sans Condensed", size: ui.size, relativeTo: ui.textStyle).weight(.semibold))
    }

    @Test func genericFamiliesPickTheSystemDesign() throws {
        #expect(OuroFont.resolve(try token(.sjTypeBody), in: cookbook, registered: { _ in false }) == .system(design: .serif))
        #expect(OuroFont.resolve(try token(.sjTypeUi), in: cookbook, registered: { _ in false }) == .system(design: .default))
        // Generic names are never looked up as families, even when the check would say yes.
        #expect(OuroFont.resolve(try token(.sjTypeBody), in: OuroThemeExtras(light: [:], dark: [:], fonts: [.sjBody: ["serif"]],
            lengths: [:], numbers: [:], shadows: [:], type: [:]), registered: { _ in true }) == .system(design: .serif))
    }

    @Test func aThemeWithoutTheFamilyFallsBackToTheSystemFont() throws {
        let body = try token(.sjTypeBody)
        #expect(OuroFont.resolve(body, in: .empty, registered: { _ in true }) == .system(design: .default))
    }

    @Test(arguments: [(100, Font.Weight.ultraLight), (200, .thin), (300, .light), (400, .regular), (500, .medium),
                      (600, .semibold), (700, .bold), (800, .heavy), (900, .black), (650, .bold), (50, .ultraLight)])
    func cssWeightsMapToSwiftUIWeights(css: Int, weight: Font.Weight) {
        #expect(OuroFont.weight(css) == weight)
    }

    @Test func registeredFamiliesComeFromCoreText() {
        // Helvetica ships with every Apple platform; Fraunces is never a system font.
        #expect(OuroFont.isRegistered("Helvetica"))
        #expect(!OuroFont.isRegistered("Fraunces"))
    }

    @Test func trackingAndLeadingScaleWithTextSize() throws {
        let eyebrow = try token(.sjTypeEyebrow)
        #expect(OuroFont.tracking(eyebrow, scale: 1) == eyebrow.tracking)
        #expect(OuroFont.tracking(eyebrow, scale: 2) == eyebrow.tracking * 2)
        let body = try token(.sjTypeBody)
        // line-height 1.5 at 16 pt: 8 pt between lines, doubled at twice the size.
        #expect(OuroFont.lineSpacing(body, scale: 1) == 8)
        #expect(OuroFont.lineSpacing(body, scale: 2) == 16)
        #expect(OuroFont.lineSpacing(eyebrow, scale: 1) == 0)
    }
}
