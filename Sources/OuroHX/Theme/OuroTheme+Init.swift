import SwiftUI

extension OuroTheme {
    /// A theme without a control radius, so its controls take its `lg` step. This is the initializer `OuroTheme` had
    /// before core v1.9.0 added `controlRadius`. It's kept so code built against OuroHX 1.7 still compiles. It forwards
    /// to the generated initializer with `controlRadius: nil`.
    public init(name: OuroThemeName, light: OuroColors, dark: OuroColors, radius: Double, extras: OuroThemeExtras, heading: [String]) {
        self.init(name: name, light: light, dark: dark, radius: radius, extras: extras, heading: heading, controlRadius: nil)
    }
}
