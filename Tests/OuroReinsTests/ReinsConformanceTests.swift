import Foundation
@testable import OuroReins
import Testing

/// The Reins protocol's section 1 (`docs/ouro-reins/PROTOCOL.md`): the screen an agent is shown. Each case is one screen
/// a driver wrote; the case names the driver in its file. `housesitter-ls.json` is what `housesitter ls` returns
/// (ourostack/housesitter, src/reins.mjs), so a change to either side fails here.
@Suite struct ReinsConformanceTests {
    static let cases: [URL] = {
        let dir = Bundle.module.url(forResource: "Conformance", withExtension: nil)!.appending(path: "cases")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().map { dir.appending(path: $0) }
    }()

    /// The rules of section 1 a screen must meet; returns each one it breaks, in words.
    static func problems(_ screen: [String: Any]) -> [String] {
        var out: [String] = []
        guard let focus = screen["focus"] as? String else { return ["focus is not a string"] }
        guard let path = screen["path"] as? [String], let last = path.last else { return ["path is not a non-empty list of names"] }
        if last != focus { out.append("path must end at the focus \(focus), but ends at \(last)") }
        if screen["state"] == nil { out.append("state is missing") }
        guard let context = screen["context"] as? [String: Any] else { return out + ["context is not an object"] }
        for key in context.keys where !path.dropLast().contains(key) {
            out.append("context names \(key), which is not above the focus")
        }
        guard let actions = screen["actions"] as? [[String: Any]] else { return out + ["actions is not a list"] }
        var seen = Set<String>()
        for action in actions {
            let name = action["name"] as? String ?? ""
            if name.isEmpty { out.append("an action has no name") }
            if !seen.insert(name).inserted { out.append("action \(name) is listed twice") }
            if !(action["title"] is String) { out.append("action \(name) has no title") }
            guard let from = action["from"] as? String, path.contains(from) else {
                out.append("action \(name) is not offered by the focus or an ancestor")
                continue
            }
            if let input = action["input"] {
                let schema = input as? [String: Any]
                if schema?["type"] as? String != "object" { out.append("action \(name) has an input that is not an object schema") }
            }
        }
        return out
    }

    @Test func everyCaseIsHere() {
        #expect(Self.cases.count >= 2)
    }

    @Test(arguments: cases) func followsSectionOne(_ url: URL) throws {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let screen = try #require(json as? [String: Any])
        #expect(Self.problems(screen) == [], "\(url.lastPathComponent)")
    }

    @Test func aScreenBreakingTheRulesIsNamed() {
        let broken: [String: Any] = [
            "focus": "recipe", "path": ["app", "recipe"], "state": [:], "context": [:],
            "actions": [["name": "x", "from": "elsewhere"]],
        ]
        let found = Self.problems(broken)
        #expect(found.contains { $0.contains("action x is not offered") })
        #expect(found.contains { $0.contains("action x has no title") })
    }
}
