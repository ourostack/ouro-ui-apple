import AppIntents

enum FixtureError: Error, CustomLocalizedStringResourceConvertible {
    case noSuchNote(String)
    case noSuchTag

    var localizedStringResource: LocalizedStringResource {
        switch self {
        // Names the fix: what to do next.
        case .noSuchNote(let id): return "There's no note \(id). Pick one from the notes list, then try again."
        // Says what went wrong and nothing more: the X-ray must report it.
        case .noSuchTag: return "Tag not found."
        }
    }
}

/// Holds the intent claims: a title, a description, and parameters with titles and descriptions.
struct OpenNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Note"
    static let description = IntentDescription("Opens a note in Xray Fixture.")
    static let openAppWhenRun = true

    @Parameter(title: "Note", description: "The note to open.")
    var note: NoteEntity

    func perform() async throws -> some IntentResult {
        guard FixtureStore.notes.contains(where: { $0.id == note.id }) else { throw FixtureError.noSuchNote(note.id) }
        return .result()
    }
}

/// A read with a result value.
struct GetNoteBodyIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Note Body"
    static let description = IntentDescription("Returns the text of a note.")

    @Parameter(title: "Note", description: "The note to read.")
    var note: NoteEntity

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let found = FixtureStore.notes.first(where: { $0.id == note.id }) else { throw FixtureError.noSuchNote(note.id) }
        return .result(value: found.body)
    }
}

/// Breaks the intent claims on purpose: no description, a parameter with no description, and an error that names
/// no fix.
struct TagNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Tag Note"

    @Parameter(title: "Tag")
    var tag: TagEntity

    func perform() async throws -> some IntentResult {
        guard FixtureStore.tags.contains(where: { $0.id == tag.id }) else { throw FixtureError.noSuchTag }
        return .result()
    }
}

struct FixtureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenNoteIntent(),
            phrases: ["Open a note in \(.applicationName)", "Open \(\.$note) in \(.applicationName)"],
            shortTitle: "Open Note",
            systemImageName: "note.text"
        )
    }
}
