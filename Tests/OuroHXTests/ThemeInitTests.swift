@testable import OuroHX
import Testing

/// The initializer from before core v1.9.0 still builds a theme, with no control radius, so its controls take the
/// `lg` step.
@Suite struct ThemeInitTests {
    @Test func thePreControlRadiusInitializerStillBuildsATheme() {
        let pearl = OuroTokens.pearl
        let theme = OuroTheme(name: pearl.name, light: pearl.light, dark: pearl.dark, radius: pearl.radius, extras: pearl.extras, heading: pearl.heading)
        #expect(theme.controlRadius == nil)
        #expect(theme.radius == pearl.radius)
        #expect(theme.heading == pearl.heading)
    }

    @Test func theGeneratedInitializerCarriesAControlRadius() {
        let cookbook = OuroTokens.cookbook
        let theme = OuroTheme(name: cookbook.name, light: cookbook.light, dark: cookbook.dark, radius: cookbook.radius, extras: cookbook.extras, heading: cookbook.heading, controlRadius: cookbook.controlRadius)
        #expect(theme.controlRadius == 9999)
    }
}
