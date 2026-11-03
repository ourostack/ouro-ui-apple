#if canImport(CoreSpotlight) && canImport(AppIntents)
public import AppIntents
public import CoreSpotlight

extension OuroAX {
    /// Indexes entities in Spotlight, the only door to Siri's personal context for third-party apps. Call it when
    /// entities change; it replaces earlier entries with the same identifiers.
    @available(iOS 18.0, macOS 15.0, *)
    public static func index<Entity: IndexedEntity>(_ entities: [Entity], in index: CSSearchableIndex = .default()) async throws {
        try await index.indexAppEntities(entities)
    }
}
#endif
