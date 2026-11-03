import AppIntents
import CoreTransferable
import UniformTypeIdentifiers

/// Holds the entity claims: a display name, described properties (but one is left undescribed on purpose),
/// Spotlight indexing, an enumerable query and a Transferable representation.
struct NoteEntity: AppEntity, IndexedEntity, Transferable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Note"
    static let defaultQuery = NoteQuery()

    let id: String

    // Property descriptions arrive with the Siri AI preview SDK (27.3); Xcode 27.2's @Property has no description.
    #if OURO_SIRI_AI_SDK || canImport(AppIntents, _version: 301.2)
    @Property(title: "Title", description: "The note's title, as the person wrote it.")
    var title: String
    #else
    @Property(title: "Title")
    var title: String
    #endif

    // Left without a description on purpose: the X-ray must report it.
    @Property(title: "Body")
    var body: String

    init(id: String, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(body)", image: .init(systemName: "note.text"))
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.title)
    }
}

struct NoteQuery: EnumerableEntityQuery, EntityStringQuery {
    func entities(for identifiers: [NoteEntity.ID]) async throws -> [NoteEntity] {
        FixtureStore.notes.filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [NoteEntity] {
        FixtureStore.notes.filter { $0.title.localizedCaseInsensitiveContains(string) }
    }

    func allEntities() async throws -> [NoteEntity] { FixtureStore.notes }

    func suggestedEntities() async throws -> [NoteEntity] { FixtureStore.notes }
}

/// Breaks the entity claims on purpose: its display name is its type name, it has no properties, it is neither
/// indexed nor enumerable, and it is not Transferable.
struct TagEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "TagEntity"
    static let defaultQuery = TagQuery()

    let id: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct TagQuery: EntityQuery {
    func entities(for identifiers: [TagEntity.ID]) async throws -> [TagEntity] {
        FixtureStore.tags.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [TagEntity] { FixtureStore.tags }
}
