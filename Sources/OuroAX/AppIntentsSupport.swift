#if canImport(AppIntents)
public import AppIntents
public import Foundation

// MARK: - The package hook

/// Lists OuroAX's App Intents metadata for an app, so intents and entities in packages reach Siri, Shortcuts and
/// Spotlight. Include it from the app's own package type:
///
/// ```swift
/// struct NotesIntentsPackage: AppIntentsPackage {
///     static var includedPackages: [any AppIntentsPackage.Type] { [OuroAXPackage.self] }
/// }
/// ```
@available(iOS 17.0, macOS 14.0, *)
public struct OuroAXPackage: AppIntentsPackage {}

// MARK: - Problems and outcomes, spoken

extension OuroAX.Problem: CustomLocalizedStringResourceConvertible {
    /// The one line Siri and Shortcuts show when an intent throws this problem.
    public var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
}

extension OuroAX.Outcome {
    /// What an intent says when it finishes: the summary, or a refusal's or failure's error message.
    public var dialogText: String {
        if state == .refused || state == .failed, let error { return error.message }
        return summary
    }

    /// ``dialogText`` as the dialog an intent returns: `.result(dialog: outcome.dialog)`.
    public var dialog: IntentDialog { IntentDialog(stringLiteral: dialogText) }
}

// MARK: - Entities and queries

/// An App Intents entity with a string identifier and the text a query matches against.
public protocol OuroAXEntity: AppEntity where ID == String {
    /// The words a person might use to find this entity: its title, folder, author. Defaults to the display title.
    var searchableText: [String] { get }
}

extension OuroAXEntity {
    public var searchableText: [String] { [String(localized: displayRepresentation.title)] }
}

/// Where a query finds its entities: the app's store, read without UI.
public protocol OuroAXEntitySource: Sendable {
    associatedtype Entity: OuroAXEntity
    /// The entities with these identifiers, in any order; a missing one is left out.
    func entities(for identifiers: [String]) async throws -> [Entity]
    /// Every entity a person could mean, for suggestions and string matching.
    func allEntities() async throws -> [Entity]
    /// The entities to suggest first. Defaults to ``allEntities()``.
    func suggestedEntities() async throws -> [Entity]
}

extension OuroAXEntitySource {
    public func suggestedEntities() async throws -> [Entity] { try await allEntities() }
}

/// An `EntityStringQuery` answered from an ``OuroAXEntitySource``: lookups by identifier, suggestions, and string
/// matching with ``OuroAX/EntityMatch``. Write only `var source`.
public protocol OuroAXEntityQuery: EntityStringQuery where Entity == Source.Entity {
    associatedtype Source: OuroAXEntitySource
    associatedtype Entity = Source.Entity
    var source: Source { get }
}

extension OuroAXEntityQuery {
    public func entities(for identifiers: [String]) async throws -> [Entity] {
        try await source.entities(for: identifiers)
    }

    public func suggestedEntities() async throws -> [Entity] {
        try await source.suggestedEntities()
    }

    /// Entities whose text matches, best first; ties keep the source's order.
    public func entities(matching string: String) async throws -> [Entity] {
        try await source.allEntities().enumerated()
            .compactMap { offset, entity in OuroAX.EntityMatch.score(string, in: entity.searchableText).map { ($0, offset, entity) } }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
            .map(\.2)
    }
}

// MARK: - Intents that return an outcome

/// An App Intent whose work returns an ``OuroAX/Outcome``: write ``outcome()`` and the default `perform()` speaks its
/// summary, or throws its problem when it was refused or failed, so Siri, Shortcuts and an agent all hear the same
/// thing.
public protocol OuroAXOutcomeIntent: AppIntent {
    /// Does the work and says what became of it.
    func outcome() async throws -> OuroAX.Outcome
}

extension OuroAXOutcomeIntent {
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await outcome()
        if outcome.state == .refused || outcome.state == .failed {
            throw outcome.error ?? OuroAX.Problem(code: outcome.state.rawValue, exit: 1, thing: outcome.action, problem: outcome.summary, fix: outcome.next.first?.command)
        }
        return .result(dialog: outcome.dialog)
    }
}

// MARK: - Siri AI Developer Preview (Xcode 27.3 beta SDK)

// `ToolIntent` exists only in the 27.3 beta SDK. AppIntents 301.1.16 is Xcode 27.2's; a newer framework, or building
// with -DOURO_SIRI_AI_SDK, turns this on. Compile-check it with Xcode 27.3 (see README, "Siri AI").
#if OURO_SIRI_AI_SDK || canImport(AppIntents, _version: 301.2)
/// A tool intent Siri can call (`@AppIntent(.tool)`) that returns an ``OuroAX/Outcome``.
@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
public typealias OuroAXToolIntent = OuroAXOutcomeIntent & ToolIntent
#endif
#endif
