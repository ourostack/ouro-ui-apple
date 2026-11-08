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
        // Helvetica ships with every Apple platform; no family has this name.
        #expect(OuroFont.isRegistered("Helvetica"))
        #expect(!OuroFont.isRegistered("Ouro No Such Family"))
    }

    @Test func aWeightResolvesToTheFamilysBolderFace() throws {
        // Avenir Next ships with iOS and macOS as static faces, regular through heavy.
        let regular = try #require(OuroFont.face(family: "Avenir Next", weight: 400))
        let semibold = try #require(OuroFont.face(family: "Avenir Next", weight: 600))
        let bold = try #require(OuroFont.face(family: "Avenir Next", weight: 700))
        #expect(regular.isExactWeight && semibold.isExactWeight && bold.isExactWeight)
        #expect(semibold.weight > regular.weight && bold.weight >= semibold.weight)
        #expect(Set([regular.postScriptName, semibold.postScriptName]).count == 2)
        #expect(!regular.postScriptName.localizedCaseInsensitiveContains("italic"))
    }

    @Test func aFamilyWithoutTheWeightSaysSoInsteadOfRenderingRegular() throws {
        // Zapfino has a single face, so it cannot supply 700.
        let face = try #require(OuroFont.face(family: "Zapfino", weight: 700))
        #expect(!face.isExactWeight)
        #expect(!OuroFont.isAvailable(family: "Zapfino", weights: [700]))
        #expect(OuroFont.isAvailable(family: "Avenir Next", weights: [400, 600, 700]))
        #expect(!OuroFont.isAvailable(family: "Ouro No Such Family", weights: [400]))
        #expect(OuroFont.face(family: "Ouro No Such Family", weight: 400) == nil)
    }

    @Test func aRegisteredFamilyRendersItsMatchedFace() throws {
        let ui = try token(.sjTypeUi)
        let extras = OuroThemeExtras(light: [:], dark: [:], fonts: [.sjUi: ["Avenir Next"]], lengths: [:], numbers: [:],
                                     shadows: [:], type: [:])
        let face = try #require(OuroFont.face(family: "Avenir Next", weight: ui.weight))
        #expect(Font.ouro(ui, in: extras) == .custom(face.postScriptName, size: ui.size, relativeTo: ui.textStyle))
    }

    @Test func trackingScalesWithTextSize() throws {
        let eyebrow = try token(.sjTypeEyebrow)
        #expect(OuroFont.tracking(eyebrow, scale: 1) == eyebrow.tracking)
        #expect(OuroFont.tracking(eyebrow, scale: 2) == eyebrow.tracking * 2)
    }

    @Test func lineSpacingTopsTheFontsOwnLineUpToCSSLineHeight() throws {
        let body = try token(.sjTypeBody)
        for registered in [{ (_: String) in false }, { $0 == "Georgia" }] {
            let natural = OuroFont.naturalLineHeight(body, in: cookbook, registered: registered)
            #expect(natural > body.size && natural < body.size * 1.5)
            // line-height 1.5 at 16 pt: the font's own line plus the spacing is 24 pt, and 48 at twice the size.
            let spacing = OuroFont.lineSpacing(body, in: cookbook, scale: 1, registered: registered)
            #expect(abs(natural + spacing - 24) < 0.001)
            let doubled = OuroFont.lineSpacing(body, in: cookbook, scale: 2, registered: registered)
            #expect(abs(natural * 2 + doubled - 48) < 0.001)
        }
        // An eyebrow's line-height 1 is tighter than any font's own line, so nothing is added (never negative).
        #expect(OuroFont.lineSpacing(try token(.sjTypeEyebrow), in: cookbook, scale: 1) == 0)
    }
}
