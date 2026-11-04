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

    /// What JavaScript's `JSON.stringify` gives for a copy with keys sorted at every level, which is what core hashes:
    /// keys in UTF-16 code-unit order (JSONSerialization's `.sortedKeys` ignores case, so it is not used), no
    /// whitespace, and strings and numbers written as JavaScript writes them. ouro-ui-core's canonical-JSON test vector
    /// pins it.
    public static func canonicalJSON(_ data: Data) throws -> Data {
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        var out = ""
        try writeCanonical(value, to: &out)
        return Data(out.utf8)
    }

    private static func writeCanonical(_ value: Any, to out: inout String) throws {
        switch value {
        case let d as [String: Any]:
            out += "{"
            for (i, k) in d.keys.sorted(by: { $0.utf16.lexicographicallyPrecedes($1.utf16) }).enumerated() {
                if i > 0 { out += "," }
                writeString(k, to: &out)
                out += ":"
                try writeCanonical(d[k]!, to: &out)
            }
            out += "}"
        case let a as [Any]:
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                try writeCanonical(v, to: &out)
            }
            out += "]"
        case let s as String:
            writeString(s, to: &out)
        case is NSNull:
            out += "null"
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { out += n.boolValue ? "true" : "false"; return }
            out += javaScriptNumber(n.doubleValue)
        default:
            throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "canonicalJSON: \(type(of: value)) is not JSON"])
        }
    }

    private static func writeString(_ s: String, to out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{8}": out += "\\b"
            case "\u{c}": out += "\\f"
            case _ where u.value < 0x20: out += String(format: "\\u%04x", u.value)
            default: out.unicodeScalars.append(u)
            }
        }
        out += "\""
    }

    // ECMAScript Number::toString: positional from 1e-6 up to 1e21, else e-notation with a signed exponent, always the
    // shortest digits that round-trip (which Swift's description also gives).
    static func javaScriptNumber(_ x: Double) -> String {
        if x == 0 { return "0" }
        if x == x.rounded(), abs(x) < 1e21 { return String(format: "%.0f", x) }
        let d = "\(x)"
        guard let e = d.firstIndex(of: "e") else { return d }
        var mantissa = String(d[..<e])
        if mantissa.hasSuffix(".0") { mantissa.removeLast(2) }
        let exp = Int(d[d.index(after: e)...]) ?? 0
        if exp >= -6 && exp < 21 { return Decimal(string: d).map { "\($0)" } ?? d }
        return mantissa + "e" + (exp < 0 ? "-" : "+") + String(abs(exp))
    }
}
