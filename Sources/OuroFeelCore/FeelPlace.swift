import CryptoKit
import Foundation

/// Place stability: reopening, relaunching or rotating keeps the reader in the same place.
///
/// It compares SHA-256 fingerprints of what was on screen, never the text itself, so a report can be shared without
/// the content (a book page, a recipe) it was measured on.
public enum FeelPlace {
    /// The fingerprint of an empty reading. It never matches, so a blank screen is never "the same place".
    public static let empty = "empty"

    /// The first 16 hex digits of the text's SHA-256.
    public static func fingerprint(_ text: String) -> String {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return empty }
        return SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Passes when every step's fingerprint equals the starting one.
    public static func compare(start: String, after steps: [String: String]) -> FeelResult {
        var findings: [FeelFinding] = []
        if start == empty { findings.append(.couldNotCheck("nothing was on screen to start with")) }
        for name in steps.keys.sorted() where start != empty && (steps[name] != start || steps[name] == empty) {
            findings.append(FeelFinding(what: "after \(name) the screen showed different content (\(steps[name]!) instead of \(start))"))
        }
        let kept = steps.count - findings.filter { !$0.unchecked }.count
        let summary = "\(kept) of \(steps.count) steps kept the place"
        return FeelResult.judged(check: FeelGenre.placeStability.rawValue, passing: summary, failing: { _ in summary },
                          measures: ["steps": Double(steps.count), "kept": Double(kept)], findings: findings)
    }
}
