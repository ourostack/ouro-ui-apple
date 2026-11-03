#if canImport(AppIntents)
import AppIntents
import Foundation
import OuroAX
import Testing

private struct Note: OuroAXEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Note"
    static let defaultQuery = NoteQuery()
    let id: String
    let title: String
    let folder: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(title)", subtitle: "\(folder)") }
    var searchableText: [String] { [title, folder] }
}

private struct Notes: OuroAXEntitySource {
    static let all = [
        Note(id: "1", title: "Café list", folder: "Home"),
        Note(id: "2", title: "Groceries", folder: "Home"),
        Note(id: "3", title: "Release notes", folder: "Work"),
    ]
    func entities(for identifiers: [String]) async throws -> [Note] { Self.all.filter { identifiers.contains($0.id) } }
    func allEntities() async throws -> [Note] { Self.all }
}

private struct NoteQuery: OuroAXEntityQuery {
    var source: Notes { Notes() }
}

private struct AddNoteIntent: OuroAXOutcomeIntent {
    static let title: LocalizedStringResource = "Add Note"
    static let description = IntentDescription("Adds a note to a folder.")
    @Parameter(title: "Title") var name: String
    var locked = false

    func outcome() async throws -> OuroAX.Outcome {
        if locked {
            return .init(action: "note.add", state: .refused, summary: "Locked.", error: .init(code: "locked", exit: 2, thing: "note", problem: "the folder is locked", fix: "unlock it in Notes"))
        }
        return .init(action: "note.add", state: .done, summary: "Added “\(name)”.")
    }
}

@Suite struct AppIntentsHelperTests {
    @Test func matchingIgnoresCaseAndAccentsAndRanksPrefixesFirst() {
        #expect(OuroAX.EntityMatch.score("cafe", in: ["Café list"]) != nil)
        #expect(OuroAX.EntityMatch.score("xyz", in: ["Café list", "Home"]) == nil)
        let prefix = OuroAX.EntityMatch.score("rel", in: ["Release notes"])!
        let inner = OuroAX.EntityMatch.score("notes", in: ["Release notes"])!
        #expect(prefix < inner)
        #expect(OuroAX.EntityMatch.score("", in: ["a"]) == nil)
    }

    @Test func theQueryAnswersFromItsSource() async throws {
        let query = NoteQuery()
        #expect(try await query.entities(for: ["2", "9"]).map(\.id) == ["2"])
        #expect(try await query.suggestedEntities().count == 3)
        #expect(try await query.entities(matching: "home").map(\.id) == ["1", "2"])
        #expect(try await query.entities(matching: "rel").map(\.id) == ["3"])
    }

    @Test func aMissingEntityIsAProblemThatNamesTheFix() {
        let problem = OuroAX.Problem.notFound(kind: "note", id: "9", fix: "find it with the Find Notes action")
        #expect(problem.code == "not-found")
        #expect(problem.message == "note 9: not found. Fix: find it with the Find Notes action.")
    }

    @Test func anOutcomeIntentSpeaksItsSummaryOrThrowsItsProblem() async throws {
        var intent = AddNoteIntent()
        intent.name = "Groceries"
        _ = try await intent.perform()
        intent.locked = true
        await #expect(throws: OuroAX.Problem(code: "locked", exit: 2, thing: "note", problem: "the folder is locked", fix: "unlock it in Notes")) {
            _ = try await intent.perform()
        }
    }

    @Test func outcomesAndProblemsSpeak() {
        let o = OuroAX.Outcome(action: "note.add", state: .done, summary: "Added “Groceries”.")
        #expect(o.dialogText == "Added “Groceries”.")
        let refused = OuroAX.Outcome(action: "note.add", state: .refused, summary: "No.", error: .init(code: "c", exit: 2, thing: "note", problem: "is locked", fix: "unlock it in Notes"))
        #expect(refused.dialogText == "note: is locked. Fix: unlock it in Notes.")
        #expect(String(localized: OuroAX.Problem(code: "c", exit: 1, thing: "x", problem: "y", fix: nil).localizedStringResource) == "x: y.")
    }

    @Test func thePackageHookIsAnAppIntentsPackage() {
        let included: [any AppIntentsPackage.Type] = [OuroAXPackage.self]
        #expect(included.count == 1)
    }
}
#endif
