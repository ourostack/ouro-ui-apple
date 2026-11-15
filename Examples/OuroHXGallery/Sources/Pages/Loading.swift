import OuroHX
import SwiftUI

final class LoadingGalleryPage: GalleryComponentPage {
    override class var page: String { "loading" }
    override class var title: String { "Loading" }
    override class var aliases: [String] { ["skeleton", "spinner", "progress"] }
    @MainActor override class var content: AnyView { AnyView(LoadingPage()) }
}

/// Loading as an app shows it: a recipe's words and picture still arriving, rows and a card in their places, spinners
/// beside what they wait for, and progress bars known and unknown.
struct LoadingPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 12) {
                OuroSkeleton(.circle, side: 48)
                OuroSkeleton(.text, lines: 3)
            }
            OuroSkeleton().frame(height: 120)
            OuroSkeleton(.row, count: 2)
            OuroSkeleton(.card)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) { OuroSpinner(label: "Saving the draft", size: .sm); Text("Saving…").font(.subheadline) }
                HStack(spacing: 8) { OuroSpinner(label: "Syncing pantry", tone: .primary); Text("Syncing your pantry").font(.subheadline) }
                HStack(spacing: 8) { OuroSpinner(label: "Importing cookbook", size: .lg, tone: .success); Text("Importing").font(.subheadline) }
            }
            OuroProgress("Uploading photos", value: 3, max: 8, showValue: true)
            OuroProgress("Downloading update", value: 72, tone: .success, showValue: true)
            OuroProgress("Preparing your cookbook", value: nil)
        }
    }
}
