import Foundation

// The report as text, Markdown and HTML: web's ax-xray renderers, with the Apple target line and a section that says
// what each lane proved.
extension AXXray.Report {
    var title: String { target.app.name }

    var targetLine: String {
        let a = target.app
        var parts = ["\(a.name) (\(a.bundleIdentifier)\(a.platform.map { ", \($0)" } ?? ""))"]
        if let c = target.commit { parts.append("at \(c)") }
        parts.append("\(a.intents) intents, \(a.entities) entities, \(a.shortcuts) App Shortcuts, \(a.skills) app skills")
        if let g = a.metadataGenerator { parts.append("metadata from Xcode tools \(g)") }
        return parts.joined(separator: "; ")
    }

    var pinLine: String { "Ouro AX for Apple claim set \(claimSet.version) (sha256 \(claimSet.hash)), checked by ax-xray \(checker.version) for Apple at \(at)." }

    var verdictLine: String {
        guard inventory.given else { return "Does not conform yet: the app has no App Intents metadata, so Siri and Shortcuts see nothing from it." }
        if conformant {
            return summary.must == 0
                ? "Conforms, trivially: claim set \(claimSet.version) has no must claims yet, so this says only that the App Intents metadata was found and read. The should claims below are the findings."
                : "Conforms: every applicable must claim holds."
        }
        let failing = claims.filter { $0.tier == "must" && $0.fail > 0 }.count
        let n = { (k: Int, what: String) in "\(k) must claim\(k == 1 ? "" : "s") \(what)" }
        return "Does not conform yet: " + [failing > 0 ? n(failing, "not holding") : nil, summary.mustSkipped > 0 ? n(summary.mustSkipped, "skipped") : nil].compactMap { $0 }.joined(separator: "; ") + "."
    }

    var countsLine: String {
        let s = summary
        return "Claims holding: \(s.holding) of \(s.claims) (must: \(s.mustHolding) of \(s.must)). Checks: \(s.checks.pass) pass, \(s.checks.fail) fail, \(s.checks.skip) skipped."
    }

    var safetyLine: String { "Intents run: \(safety.ok ? "refusals only, on a disposable device" : "none") (\(safety.checks.map { "\($0.name): \($0.ok ? "yes" : "no")" }.joined(separator: ", ")))." }
    var effectsLine: String { effects.isEmpty ? "Effects the X-ray caused: none recorded." : "Effects the X-ray caused: \(effects.map { "\($0.surface): \($0.note)" }.joined(separator: "; "))." }

    var ordered: [ClaimSummary] {
        claims.enumerated().sorted { a, b in
            let (x, y) = (a.element, b.element)
            if x.holds != y.holds { return !x.holds }
            if (x.fail > 0) != (y.fail > 0) { return x.fail > 0 }
            if x.tier != y.tier { return x.tier == "must" }
            if x.fail != y.fail { return x.fail > y.fail }
            return a.offset < b.offset
        }.map(\.element)
    }

    func mark(_ c: ClaimSummary) -> String { c.holds ? "✓" : c.fail > 0 ? "✗" : "–" }

    static let laneNames: [AXXray.Lane: String] = [
        .metadata: "App Intents metadata", .appIntentsTesting: "AppIntentsTesting", .skillsLint: "skills linter",
        .siriEvaluations: "SiriEvaluations", .person: "a person",
    ]

    func laneLine(_ l: Coverage.LaneCoverage) -> String {
        let name = Self.laneNames[l.lane]!
        let ran = l.lane == .person ? "left for a person" : l.ran ? "ran\(l.ranOn.map { " (\($0))" } ?? "")" : "did not run"
        return "\(name): \(ran); settled \(l.settled.count) of \(l.claims.count)\(l.open.isEmpty ? "" : ", open: \(l.open.joined(separator: ", "))")."
    }

    /// Plain text, for a terminal.
    public func text(max: Int = 6) -> String {
        var out = ["ax-xray: \(targetLine)", pinLine, verdictLine, countsLine, coverage.statement, safetyLine, effectsLine, ""]
        for c in ordered {
            out.append("\(mark(c)) \(c.id) [\(c.tier)] \(c.rule) (\(c.pass) of \(c.pass + c.fail)\(c.skip > 0 ? ", \(c.skip) skipped" : ""))")
            for f in c.failing.prefix(max) { out.append("    \(f.surface): \(f.note)") }
            if c.failing.count > max { out.append("    … \(c.failing.count - max) more") }
            if c.fail > 0 { out.append("    Fix: \(c.fix)") }
            if c.pass + c.fail == 0, let s = c.skipped.first { out.append("    \(s.note)") }
        }
        return out.joined(separator: "\n") + "\n"
    }

    static func md(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }

    var bySurface: [(String, [AXXray.CheckResult])] {
        var keys: [String] = []
        var by: [String: [AXXray.CheckResult]] = [:]
        for r in results {
            if by[r.surface] == nil { keys.append(r.surface) }
            by[r.surface, default: []].append(r)
        }
        return keys.map { ($0, by[$0]!) }
    }

    /// Markdown, for a pull request or a desk.
    public func markdown() -> String {
        let md = Self.md
        var out = [
            "# AX X-ray: \(title)", "",
            "\(pinLine) Target: \(md(targetLine)).", "",
            "**\(verdictLine)** \(countsLine)", "",
            "## What this proves", "",
            coverage.statement, "",
        ]
        out += coverage.lanes.map { "- \(laneLine($0))" }
        out += ["", safetyLine, "", effectsLine, "",
                "| | Claim | Tier | Checked by | Rule | Pass | Fail | Skip |", "|---|---|---|---|---|---|---|---|"]
        out += ordered.map { "| \(mark($0)) | `\($0.id)` | \($0.tier) | \(Self.laneNames[$0.checkedBy]!) | \(md($0.rule)) | \($0.pass) | \($0.fail) | \($0.skip) |" }
        out += ["", "## What fails, and the fix", ""]
        let failing = ordered.filter { $0.fail > 0 }
        if failing.isEmpty { out += ["Nothing the X-ray checked fails.", ""] }
        for c in failing {
            out += ["### `\(c.id)`: \(c.rule)", "", "Why: \(c.why)", "", "Fix: \(c.fix)", "", "Source: <\(c.evidence.source)>", ""]
            out += c.failing.map { "- **\(md($0.surface))**: \(md($0.note))" }
            out.append("")
        }
        out += ["## Open: what needs SiriEvaluations or a person", ""]
        for c in ordered where c.pass + c.fail == 0 {
            out.append("- `\(c.id)` (\(Self.laneNames[c.checkedBy]!)): \(md(c.skipped.first?.note ?? ""))")
        }
        out += ["", "## Every surface", "", "| Surface | Holds | Fails | Skipped |", "|---|---|---|---|"]
        for (k, rs) in bySurface {
            let ids = { (v: AXXray.Verdict) in rs.filter { $0.verdict == v }.map { "`\($0.claim)`" }.joined(separator: " ") }
            out.append("| \(md(k)) | \(ids(.pass)) | \(ids(.fail)) | \(ids(.skip)) |")
        }
        return out.joined(separator: "\n") + "\n"
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// One HTML page with no external resources, light and dark.
    public func html() -> String {
        let esc = Self.esc
        let claims = ordered
        func cell(_ rs: [AXXray.CheckResult], _ id: String) -> String {
            let r = rs.filter { $0.claim == id }
            guard !r.isEmpty else { return "<td></td>" }
            let v = r.contains { $0.verdict == .fail } ? "fail" : r.contains { $0.verdict == .pass } ? "pass" : "skip"
            return "<td class=\"\(v)\" title=\"\(esc(r.map { "\($0.verdict.rawValue): \($0.note)" }.joined(separator: "\n")))\">\(v == "pass" ? "✓" : v == "fail" ? "✗" : "–")</td>"
        }
        let details = claims.map { c in
            let body = c.fail > 0
                ? "<p><strong>Fix:</strong> \(esc(c.fix))</p><ul>\(c.failing.map { "<li><code>\(esc($0.surface))</code>: \(esc($0.note))</li>" }.joined())</ul>"
                : c.pass + c.fail == 0 ? "<p class=\"open\">\(esc(c.skipped.first?.note ?? ""))</p>" : ""
            return "<details\(c.fail > 0 ? " open" : "")><summary class=\"\(c.holds ? "holds" : c.fail > 0 ? "fails" : "open")\">\(mark(c)) <code>\(esc(c.id))</code> [\(c.tier)] \(esc(c.rule)) (\(c.pass) of \(c.pass + c.fail)\(c.skip > 0 ? ", \(c.skip) skipped" : "")) <span class=\"lane\">\(esc(Self.laneNames[c.checkedBy]!))</span></summary><p>\(esc(c.why)) <a href=\"\(esc(c.evidence.source))\">Apple</a></p>\(body)</details>"
        }.joined(separator: "\n")
        let rows = bySurface.map { k, rs in "<tr><th scope=\"row\"><code>\(esc(k))</code></th>\(claims.map { cell(rs, $0.id) }.joined())</tr>" }.joined(separator: "\n")
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AX X-ray: \(esc(title))</title><style>
        :root{--fg:#1b1b1f;--bg:#fff;--line:#d0d0d7;--muted:#5b5b66;--pass-bg:#e6f4ea;--pass:#14532d;--fail-bg:#fde8e8;--fail:#7f1d1d;--skip-bg:#f3f3f5}
        @media (prefers-color-scheme:dark){:root{--fg:#e8e8ee;--bg:#151518;--line:#3a3a44;--muted:#a3a3ad;--pass-bg:#12351f;--pass:#bbf7d0;--fail-bg:#3b1414;--fail:#fecaca;--skip-bg:#26262c}}
        body{font:14px/1.5 system-ui,sans-serif;margin:2rem;color:var(--fg);background:var(--bg)}h1{font-size:1.5rem}code{font:12px ui-monospace,monospace}
        main{max-width:72rem}table{border-collapse:collapse;margin:1rem 0;display:block;overflow-x:auto}th,td{border:1px solid var(--line);padding:.25rem .5rem;text-align:left;vertical-align:top}
        th.v{writing-mode:vertical-rl;transform:rotate(180deg);font-weight:500;white-space:nowrap}td.pass{background:var(--pass-bg);color:var(--pass);text-align:center}td.fail{background:var(--fail-bg);color:var(--fail);text-align:center}td.skip{background:var(--skip-bg);text-align:center}
        .holds{color:var(--pass)}.fails{color:var(--fail)}.open,.lane{color:var(--muted)}.lane{font-size:12px;margin-left:.5rem}details{margin:.5rem 0}summary{cursor:pointer}a{color:inherit}
        @media (max-width:600px){body{margin:1rem}}
        </style></head><body><main>
        <h1>AX X-ray: \(esc(title))</h1>
        <p>\(esc(pinLine)) \(esc(targetLine)).</p>
        <p><strong>\(esc(verdictLine))</strong> \(esc(countsLine))</p>
        <h2>What this proves</h2>
        <p>\(esc(coverage.statement))</p>
        <ul>\(coverage.lanes.map { "<li>\(esc(laneLine($0)))</li>" }.joined())</ul>
        <p>\(esc(safetyLine))</p>
        <p>\(esc(effectsLine))</p>
        <h2>Claims</h2>
        \(details)
        <h2>Every surface</h2>
        <table><thead><tr><th>Surface</th>\(claims.map { "<th class=\"v\" scope=\"col\"><code>\(esc($0.id))</code></th>" }.joined())</tr></thead><tbody>
        \(rows)
        </tbody></table></main></body></html>

        """
    }
}
