public import Foundation

/// The App Intents X-ray: checks an app's App Intents against Ouro AX for Apple's claims, from outside the app, by
/// bundle identifier. It reads the bundle's compiled App Intents metadata, merges what AppIntentsTesting saw in a
/// behaviour run, and reports in web's ax-xray shape. See docs/decisions/2026-11-03-ax-xray.md.
public enum AXXray {
    /// The checker's version, in every report.
    public static let version = "0.2.0"

    /// How a claim is checked, which is also what a report can say it proved. Same values as core's `checkedBy`.
    public enum Lane: String, Codable, Sendable, Hashable, CaseIterable {
        case metadata = "app-intents-metadata"
        case appIntentsTesting = "app-intents-testing"
        case skillsLint = "skills-lint"
        case siriEvaluations = "siri-evaluations"
        case person
    }

    public enum Verdict: String, Codable, Sendable, Hashable { case pass, fail, skip }

    /// One claim, as core publishes it in `apple.claims.json`.
    public struct Claim: Codable, Sendable, Hashable {
        public struct Evidence: Codable, Sendable, Hashable {
            public var basis: String
            public var source: String
            public var finding: String
        }

        public var id: String
        public var surface: String
        public var tier: String
        public var applies: String
        public var appliesTo: [String]
        public var checkedBy: Lane
        public var rule: String
        public var why: String
        public var evidence: Evidence
        public var check: String
        public var fix: String
    }

    /// A claim set and the hash a report pins it by.
    public struct ClaimSet: Sendable, Hashable {
        public var version: String
        public var claims: [Claim]
        /// SHA-256 of the canonical JSON (keys sorted at every level, no spaces), the same rule as core's `claimSetHash`.
        public var hash: String

        public func claim(_ id: String) -> Claim? { claims.first { $0.id == id } }

        /// Reads a claim set from `apple.claims.json`'s bytes.
        public init(data: Data) throws {
            struct Raw: Decodable { var version: String; var claims: [Claim] }
            let raw = try JSONDecoder().decode(Raw.self, from: data)
            version = raw.version
            claims = raw.claims
            hash = try AXXray.sha256Hex(AXXray.canonicalJSON(data))
        }

        /// The claim set vendored from ouro-ui-core, pinned in core-provenance.json.
        public static func bundled() throws -> ClaimSet {
            guard let url = Bundle.module.url(forResource: "apple.claims", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "apple.claims.json is missing from OuroAXTesting's resources"])
            }
            return try ClaimSet(data: Data(contentsOf: url))
        }
    }

    /// JSON with keys sorted at every level and no whitespace or escaped slashes: what JavaScript's
    /// `JSON.stringify` gives for a key-sorted copy, which is what core hashes.
    public static func canonicalJSON(_ data: Data) throws -> Data {
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
    }
}
