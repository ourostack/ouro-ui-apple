public import Foundation

/// Ouro HX's component claims, vendored from ouro-ui-core (`components.claims.json`, pinned by hash in
/// core-provenance.json): what Button, Empty, Alert, Sheet and Toast promise on every platform. Core's page is
/// https://github.com/ourostack/ouro-ui-core/blob/main/standard/hx/components.md.
public enum OuroHXClaims {
    public enum Tier: String, Sendable, Decodable { case must, should }

    public struct Claim: Sendable, Hashable, Decodable {
        public var id: String
        public var tier: Tier
        /// Web's component names: button, empty, alert, sheet, toast.
        public var appliesTo: [String]
        public var rule: String
        public var why: String
        /// How each platform ("web", "apple") proves it.
        public var checks: [String: String]
        public var fix: String
    }

    public struct ClaimSet: Sendable, Hashable, Decodable {
        public var version: String
        public var claims: [Claim]
        public func claim(_ id: String) -> Claim? { claims.first { $0.id == id } }
    }

    /// The vendored set.
    public static func components() throws -> ClaimSet {
        guard let url = Bundle.module.url(forResource: "components.claims", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "components.claims.json is missing from OuroHXTesting's resources"])
        }
        return try JSONDecoder().decode(ClaimSet.self, from: Data(contentsOf: url))
    }
}
