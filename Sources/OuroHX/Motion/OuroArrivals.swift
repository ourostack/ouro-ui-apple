public import SwiftUI

extension EnvironmentValues {
    /// Whether kit components play their arrival as they appear, such as ``OuroEmptyState``'s cascade. On by default.
    ///
    /// Turn it off with ``SwiftUICore/View/ouroArrivals(_:)`` for a still render: a snapshot test, an `ImageRenderer`
    /// capture or a headless screenshot. An arrival starts from a clear first frame, and a still render draws that
    /// frame, so without this the component comes out blank.
    @Entry public var ouroArrivals = true
}

extension View {
    /// Whether kit components in this view play their arrival as they appear. Pass `false` for still renders, so each
    /// component is drawn settled: `OuroEmptyState(...).ouroArrivals(false)`.
    public func ouroArrivals(_ enabled: Bool) -> some View { environment(\.ouroArrivals, enabled) }
}
