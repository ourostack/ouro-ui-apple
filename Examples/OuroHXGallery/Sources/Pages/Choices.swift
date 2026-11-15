import OuroHX
import SwiftUI

final class ChoicesGalleryPage: GalleryComponentPage {
    override class var page: String { "choices" }
    override class var title: String { "Choices" }
    override class var aliases: [String] { ["checkbox", "checkboxes", "segmented", "segmentedcontrol"] }
    @MainActor override class var content: AnyView { AnyView(ChoicesPage()) }
}

struct ChoicesPage: View {
    @State private var view = "list"
    @State private var units = "metric"
    @State private var basket = [true, false, true]
    @State private var email = true
    @State private var agreed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OuroSegmentedControl("View", selection: $view, hideLabel: true, items: [
                OuroSegment("List", value: "list"),
                OuroSegment("Grid", value: "grid"),
                OuroSegment("Board", value: "board", disabled: true),
            ])
            OuroSegmentedControl("Units", selection: $units, fullWidth: true, items: [
                OuroSegment("Metric", value: "metric"),
                OuroSegment("US", value: "us"),
            ])
            VStack(alignment: .leading, spacing: 0) {
                OuroCheckbox("Whole basket", isOn: Binding(
                    get: { basket.allSatisfy { $0 } },
                    set: { all in basket = basket.map { _ in all } }
                ), indeterminate: basket.contains(true) && !basket.allSatisfy { $0 })
                ForEach(Array(["Lemons", "Orzo", "Peas"].enumerated()), id: \.offset) { i, name in
                    OuroCheckbox(name, isOn: $basket[i]).padding(.leading, 32)
                }
            }
            OuroCheckbox("Email me new recipes", isOn: $email, description: "One a week, on Sundays.")
            OuroCheckbox("I agree to the terms", isOn: $agreed, error: agreed ? nil : "Agree to the terms to continue.", required: true)
            OuroCheckbox("Archived", isOn: .constant(true)).disabled(true)
        }
    }
}
