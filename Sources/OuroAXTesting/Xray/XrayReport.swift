public import Foundation

extension AXXray {
    /// A report in web's ax-xray shape, with an Apple target and a coverage section that says, lane by lane, what was
    /// proved and what is left for SiriEvaluations or a person.
    public struct Report: Codable, Sendable, Hashable {
        public struct Checker: Codable, Sendable, Hashable {
            public var version: String
            public var platform: String
        }

        public struct ClaimSetPin: Codable, Sendable, Hashable {
            public var version: String
            public var hash: String
        }

        public struct Target: Codable, Sendable, Hashable {
            public var commit: String?
            public var app: App
            public struct App: Codable, Sendable, Hashable {
                public var name: String
                public var bundleIdentifier: String
                public var platform: String?
                public var intents: Int
                public var entities: Int
                public var shortcuts: Int
                public var skills: Int
                /// The Xcode tools that wrote the metadata.
                public var metadataGenerator: String?
            }
        }

        public struct Safety: Codable, Sendable, Hashable {
            public struct Check: Codable, Sendable, Hashable {
                public var name: String
                public var ok: Bool
                public var note: String
            }
            /// True when intents were run (refusals only), which needs a disposable device.
            public var ok: Bool
            public var checks: [Check]
        }

        public struct InventoryPin: Codable, Sendable, Hashable {
            public var given: Bool
            public var surfaces: [String]
        }

        public struct Effect: Codable, Sendable, Hashable {
            public var surface: String
            public var note: String
        }

        public struct Summary: Codable, Sendable, Hashable {
            public struct Checks: Codable, Sendable, Hashable { public var pass: Int; public var fail: Int; public var skip: Int }
            public var claims: Int
            public var holding: Int
            public var must: Int
            public var mustHolding: Int
            public var mustSkipped: Int
            public var checks: Checks
            public var score: Double?
        }

        public struct ClaimSummary: Codable, Sendable, Hashable {
            public var id: String
            public var surface: String
            public var tier: String
            public var applies: String
            public var appliesTo: [String]
            public var checkedBy: Lane
            public var rule: String
            public var why: String
            public var evidence: Claim.Evidence
            public var check: String
            public var fix: String
            public var pass: Int
            public var fail: Int
            public var skip: Int
            public var holds: Bool
            public var failing: [CheckResult]
            public var skipped: [CheckResult]
        }

        /// Per lane: whether it ran, and the claims it settled or left open.
        public struct Coverage: Codable, Sendable, Hashable {
            public struct LaneCoverage: Codable, Sendable, Hashable {
                public var lane: Lane
                public var ran: Bool
                public var ranOn: String?
                public var claims: [String]
                public var settled: [String]
                public var open: [String]
            }
            public var statement: String
            public var lanes: [LaneCoverage]
            public var provedByAppIntentsTesting: [String]
            public var needsSiriEvaluations: [String]
            public var needsPerson: [String]
        }

        public var tool: String = "ax-xray"
        public var checker: Checker
        public var claimSet: ClaimSetPin
        public var at: String
        public var target: Target
        public var safety: Safety
        public var inventory: InventoryPin
        public var effects: [Effect]
        public var conformant: Bool
        public var summary: Summary
        public var coverage: Coverage
        public var claims: [ClaimSummary]
        public var results: [CheckResult]
    }

    /// The report for one app: checks the claims against the evidence and summarises them the way web's X-ray does.
    public static func report(
        _ set: ClaimSet, _ evidence: Evidence, name: String, bundleIdentifier: String, platform: String?, commit: String?,
        at: Date = Date()
    ) -> Report {
        let results = check(set, evidence)
        let inv = evidence.inventory
        let claims: [Report.ClaimSummary] = set.claims.compactMap { c in
            let rs = results.filter { $0.claim == c.id }
            guard !rs.isEmpty else { return nil }
            let n = { (v: Verdict) in rs.filter { $0.verdict == v }.count }
            return .init(id: c.id, surface: c.surface, tier: c.tier, applies: c.applies, appliesTo: c.appliesTo, checkedBy: c.checkedBy, rule: c.rule, why: c.why, evidence: c.evidence, check: c.check, fix: c.fix,
                         pass: n(.pass), fail: n(.fail), skip: n(.skip), holds: n(.fail) == 0 && n(.pass) > 0,
                         failing: rs.filter { $0.verdict == .fail }, skipped: rs.filter { $0.verdict == .skip })
        }
        let count = { (v: Verdict) in results.filter { $0.verdict == v }.count }
        let must = claims.filter { $0.tier == "must" }
        let pass = count(.pass), fail = count(.fail)
        var surfaces: [String] = []
        if let inv {
            if !inv.intents.isEmpty { surfaces.append("app-intent") }
            if !inv.entities.isEmpty { surfaces.append("app-entity") }
            if let p = evidence.probe, p.steps.contains(where: { $0.probe == "view-annotations" && ($0.count ?? 0) > 0 }) { surfaces.append("view-annotation") }
        }
        if let s = evidence.skills, !s.bundles.isEmpty { surfaces.append("app-skill") }
        let refusals = evidence.probe?.steps.filter { $0.probe == "refusal" } ?? []
        let readBacks = evidence.probe?.steps.filter { $0.probe == "export-resolve" } ?? []
        let readsOnly = refusals.isEmpty && readBacks.isEmpty
        let safety = Report.Safety(ok: evidence.probe?.refusalsAllowed ?? false, checks: [
            .init(name: "reads only", ok: readsOnly, note: readsOnly
                ? "metadata is read from the built app; the probe ran entity queries, Spotlight, view annotations and export"
                : "the probe also ran \(refusals.count) refusal\(refusals.count == 1 ? "" : "s") and \(readBacks.count) import read-back\(readBacks.count == 1 ? "" : "s"), listed under effects, on a disposable device"),
            .init(name: "disposable device", ok: evidence.probe?.refusalsAllowed ?? false,
                  note: evidence.probe.map { $0.refusalsAllowed ? "refusal runs allowed on \($0.ranOn)" : "refusal runs off" } ?? "no behaviour run"),
        ])
        let effects = readBacks.map { Report.Effect(surface: "entity \($0.subject)", note: "read an exported entity back through the app's import") } + refusals.map { Report.Effect(surface: "intent \($0.subject)", note: $0.error.map { AXXray.unreachable($0) ? "tried; the call never reached the app" : AXXray.askedAgain($0) != nil ? "tried; the system asked for the value again, so the intent never ran" : "run with an entity reference nothing can match; refused" } ?? "run with an entity reference nothing can match; it ran") }

        func lane(_ l: Lane, ran: Bool, on: String?) -> Report.Coverage.LaneCoverage {
            let ids = claims.filter { $0.checkedBy == l }
            return .init(lane: l, ran: ran, ranOn: on, claims: ids.map(\.id), settled: ids.filter { $0.pass + $0.fail > 0 }.map(\.id), open: ids.filter { $0.pass + $0.fail == 0 }.map(\.id))
        }
        let lanes = [
            lane(.metadata, ran: inv != nil, on: inv?.generator.map { "metadata written by Xcode tools \($0)" }),
            lane(.skillsLint, ran: evidence.skills.map { !$0.bundles.isEmpty } ?? false, on: nil),
            lane(.appIntentsTesting, ran: evidence.probe != nil, on: evidence.probe?.ranOn),
            lane(.siriEvaluations, ran: evidence.siri != nil, on: evidence.siri?.ranOn),
            lane(.person, ran: false, on: nil),
        ]
        let testing = lanes[2]
        let coverage = Report.Coverage(
            statement: "This report does not prove what Siri will do. The metadata and the skills linter show what the app declares; AppIntentsTesting shows that its queries, Spotlight index, annotations and errors behave, without Siri. Only SiriEvaluations runs show whether Siri calls the right intent, and some claims need a person on a device.",
            lanes: lanes,
            provedByAppIntentsTesting: testing.settled,
            needsSiriEvaluations: claims.filter { $0.checkedBy == .siriEvaluations && $0.pass + $0.fail == 0 }.map(\.id),
            needsPerson: claims.filter { $0.checkedBy == .person }.map(\.id)
        )
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return Report(
            checker: .init(version: version, platform: "apple"),
            claimSet: .init(version: set.version, hash: set.hash),
            at: fmt.string(from: at),
            target: .init(commit: commit, app: .init(name: name, bundleIdentifier: bundleIdentifier, platform: platform, intents: inv?.intents.count ?? 0, entities: inv?.entities.count ?? 0, shortcuts: inv?.shortcuts.count ?? 0, skills: evidence.skills?.skills.count ?? 0, metadataGenerator: inv?.generator)),
            safety: safety,
            inventory: .init(given: inv != nil, surfaces: surfaces),
            effects: effects,
            conformant: inv != nil && must.allSatisfy { $0.fail == 0 && $0.skip == 0 },
            summary: .init(claims: claims.count, holding: claims.filter(\.holds).count, must: must.count, mustHolding: must.filter(\.holds).count, mustSkipped: must.filter { $0.skip > 0 }.count,
                           checks: .init(pass: pass, fail: fail, skip: count(.skip)), score: pass + fail > 0 ? (1000 * Double(pass) / Double(pass + fail)).rounded() / 10 : nil),
            coverage: coverage,
            claims: claims,
            results: results
        )
    }
}

extension AXXray.Report {
    /// Pretty JSON with sorted keys, so two runs diff cleanly.
    public func json() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self) + Data("\n".utf8)
    }
}
