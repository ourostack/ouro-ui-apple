import SwiftUI

extension OuroTheme {
    /// A theme without a control radius, so its controls take its `lg` step. This is the initializer `OuroTheme` had
    /// before core v1.9.0 added `controlRadius`. It's kept so code built against OuroHX 1.7 still compiles. It forwards
    /// to the generated initializer with `controlRadius: nil`. It keeps its old defaults; a call that leaves out
    /// `controlRadius` picks this one, since it defaults fewer arguments, and gets the same theme.
    public init(name: OuroThemeName, light: OuroColors, dark: OuroColors, radius: Double, extras: OuroThemeExtras = .empty, heading: [String] = []) {
        self.init(name: name, light: light, dark: dark, radius: radius, extras: extras, heading: heading, controlRadius: nil)
    }
}
