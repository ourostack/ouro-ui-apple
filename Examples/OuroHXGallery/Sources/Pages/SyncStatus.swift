import OuroHX
import SwiftUI

final class SyncStatusGalleryPage: GalleryComponentPage {
    override class var page: String { "sync" }
    override class var title: String { "Sync status" }
    override class var aliases: [String] { ["syncstatus"] }
    @MainActor override class var content: AnyView { AnyView(SyncStatusPage()) }
}

struct SyncStatusPage: View {
    @State private var state = OuroSyncState.error
    @State private var retries = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OuroSyncStatus(state) {
                retries += 1
                state = .saving
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    state = .saved
                }
            }
            .accessibilityIdentifier("sync.live")
            Divider()
            ForEach(OuroSyncState.allCases, id: \.self) { s in
                OuroSyncStatus(s, labels: OuroSyncStatusLabels(saved: "Recipe saved", saving: "Saving recipe…"))
            }
        }
    }
}
