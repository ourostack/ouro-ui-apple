public import SwiftUI

/// Web's `Empty` is `OuroEmptyState` here.
@available(*, unavailable, renamed: "OuroEmptyState", message: "Ouro HX for Apple calls web's Empty OuroEmptyState.")
public typealias OuroEmpty<Action: View> = OuroEmptyState<Action>

/// Web's `Alert` is `OuroBanner` here: on Apple, an alert is SwiftUI's modal `.alert`.
@available(*, unavailable, renamed: "OuroBanner", message: "Ouro HX for Apple calls web's Alert OuroBanner; for a modal question use SwiftUI's .alert or .confirmationDialog.")
public typealias OuroAlert<Action: View> = OuroBanner<Action>
