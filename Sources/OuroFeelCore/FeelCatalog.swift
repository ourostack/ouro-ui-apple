public import Foundation

/// Every principle and the genres it holds, as data: `docs/ouro-feel/checks.json` is this, and ui.ouroboros.bot draws
/// its Ouro Feel page from that file. A test (`CatalogTests`) fails when the file and this disagree; rewrite it with
/// `OURO_FEEL_WRITE_CATALOG=1 swift test --filter CatalogTests`.
public struct FeelCatalog: Codable, Equatable, Sendable {
    public struct Check: Codable, Equatable, Sendable {
        public var name: String
        public var good: String
        public var calls: [String]
    }

    public struct Principle: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var promise: String
        public var checks: [Check]
    }

    public var principles: [Principle]

    public static var current: FeelCatalog {
        FeelCatalog(principles: FeelPrinciple.all.map { p in
            Principle(id: p.id, name: p.name, promise: p.promise,
                      checks: p.checks.map { Check(name: $0.name, good: $0.good, calls: $0.calls) })
        })
    }

    /// The catalog as the committed file holds it: pretty-printed, keys sorted, with a final newline.
    public var json: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return ((try? encoder.encode(self)) ?? Data()) + Data("\n".utf8)
    }
}
