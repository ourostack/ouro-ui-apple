import AppIntents
import CoreSpotlight
import SwiftUI

/// The fixture's data: three notes and two tags, the same on every launch.
enum FixtureStore {
    static let notes: [NoteEntity] = [
        .init(id: "note-groceries", title: "Groceries", body: "Milk, eggs, lemons"),
        .init(id: "note-trip", title: "Trip plan", body: "Train at nine"),
        .init(id: "note-ideas", title: "Ideas", body: "A tiny app"),
    ]
    static let tags: [TagEntity] = [.init(id: "tag-home"), .init(id: "tag-work")]
}

@main
struct FixtureApp: App {
    var body: some Scene {
        WindowGroup {
            NotesView()
                .task { try? await CSSearchableIndex.default().indexAppEntities(FixtureStore.notes) }
        }
    }
}

/// The first screen lists the notes. Each row is annotated with its entity, and the first one is selected.
struct NotesView: View {
    @State private var selection: NoteEntity.ID? = FixtureStore.notes.first?.id

    var body: some View {
        List(FixtureStore.notes, selection: $selection) { note in
            VStack(alignment: .leading) {
                Text(note.title).font(.headline)
                Text(note.body).font(.subheadline)
            }
            .appEntityIdentifier(EntityIdentifier(for: note))
        }
        .navigationTitle("Notes")
    }
}
