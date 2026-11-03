import Foundation
public import OuroAXSkillsLint

extension AXXray {
    /// One claim checked on one surface: an app, an intent, a parameter, an entity, a property, a skill bundle or a skill.
    public struct CheckResult: Codable, Sendable, Hashable {
        public var claim: String
        public var surface: String
        public var verdict: Verdict
        public var note: String
        public init(claim: String, surface: String, verdict: Verdict, note: String) {
            self.claim = claim
            self.surface = surface
            self.verdict = verdict
            self.note = note
        }
    }

    /// Everything a check reads. Only `inventory` is required; each missing lane's claims are skipped, with a note that
    /// says what would check them.
    public struct Evidence: Sendable {
        public var inventory: Inventory?
        public var skills: SkillsLint.Report?
        public var probe: ProbeResult?
        public var siri: SiriResults?
        public init(inventory: Inventory?, skills: SkillsLint.Report? = nil, probe: ProbeResult? = nil, siri: SiriResults? = nil) {
            self.inventory = inventory
            self.skills = skills
            self.probe = probe
            self.siri = siri
        }
    }

    /// The linter codes each skill claim covers.
    static let skillCodes: [String: Set<String>] = [
        "skill.bundle-shape": ["bundle-name", "stray-file", "skills-folder-missing", "skill-md-missing"],
        "skill.names": ["skill-name", "duplicate-name", "name-mismatch"],
        "skill.frontmatter": ["frontmatter-missing", "frontmatter-field", "frontmatter-duplicate", "name-missing", "description-missing", "not-utf8"],
        "skill.body": ["body-too-long", "body-empty", "intent-type-name"],
    ]

    /// Siri expectation kinds, by the claim they evidence.
    static let siriKinds: [String: String] = [
        "intent.siri-calls": "calls", "intent.siri-says-what-happened": "response", "entity.siri-finds": "finds",
        "annotation.siri-onscreen": "onscreen", "skill.loads": "loads",
    ]

    /// Checks every claim in the set against the evidence, in claim order.
    public static func check(_ set: ClaimSet, _ evidence: Evidence) -> [CheckResult] {
        guard let inventory = evidence.inventory else {
            return set.claims.map { CheckResult(claim: $0.id, surface: "app", verdict: .skip, note: "no App Intents metadata in the app, so there is nothing to check") }
        }
        return set.claims.flatMap { claim -> [CheckResult] in
            let results: [CheckResult]
            switch claim.checkedBy {
            case .metadata: results = metadataChecks(claim.id, inventory)
            case .skillsLint: results = skillChecks(claim.id, evidence.skills)
            case .appIntentsTesting: results = behaviourChecks(claim.id, inventory, evidence.probe)
            case .siriEvaluations: results = siriChecks(claim.id, evidence.siri)
            case .person: results = personChecks(claim.id, inventory)
            }
            return results.map { CheckResult(claim: claim.id, surface: $0.surface, verdict: $0.verdict, note: $0.note) }
        }
    }

    // A result before its claim is attached.
    typealias R = CheckResult
    static func r(_ surface: String, _ verdict: Verdict, _ note: String) -> R { R(claim: "", surface: surface, verdict: verdict, note: note) }

    static func metadataChecks(_ id: String, _ inv: Inventory) -> [R] {
        let entities = inv.entities.filter { !$0.transient }
        switch id {
        case "intent.title":
            return inv.intents.map { i in
                i.title.isEmpty ? r("intent \(i.identifier)", .fail, "has no title")
                    : i.title == i.identifier ? r("intent \(i.identifier)", .fail, "its title is its type name")
                    : r("intent \(i.identifier)", .pass, "“\(i.title)”")
            }
        case "intent.description":
            return inv.intents.map { i in
                guard let d = i.description else { return r("intent \(i.identifier)", .fail, "“\(i.title)” has no description") }
                return d == i.title ? r("intent \(i.identifier)", .fail, "its description only repeats its title") : r("intent \(i.identifier)", .pass, "“\(clip(d))”")
            }
        case "intent.parameter-title":
            return inv.intents.flatMap { i in
                i.parameters.map { p in p.title.isEmpty ? r("intent \(i.identifier) · \(p.name)", .fail, "has no title") : r("intent \(i.identifier) · \(p.name)", .pass, "“\(p.title)”") }
            }
        case "intent.parameter-description":
            return inv.intents.flatMap { i in
                i.parameters.map { p in
                    p.description.map { r("intent \(i.identifier) · \(p.name)", .pass, "“\(clip($0))”") }
                        ?? r("intent \(i.identifier) · \(p.name)", .fail, "“\(p.title.isEmpty ? p.name : p.title)” has no description")
                }
            }
        case "intent.tool":
            guard !inv.intents.isEmpty else { return [r("app", .skip, "the app has no intents")] }
            let schema = inv.intents.filter { !$0.schemas.isEmpty }.map(\.identifier)
            let tools = inv.intents.filter { $0.isTool == true }.map(\.identifier)
            if !schema.isEmpty || !tools.isEmpty {
                return [r("app", .pass, "\(tools.count) tool intent\(tools.count == 1 ? "" : "s"), \(schema.count) adopting a schema: \(list(tools + schema))")]
            }
            if !inv.marksTools {
                // A 27.3 build whose metadata has no tool marker this checker knows is the checker's gap, not the app's.
                return [r("app", .skip, inv.isSiriAISDK
                    ? "metadata from Xcode tools \(inv.generator ?? "?") has no tool marker ax-xray \(version) recognises, and no intent adopts a schema; until a 27.3 fixture pins the field, this skips"
                    : "metadata from Xcode tools \(inv.generator ?? "of unknown version") cannot mark tool intents, and no intent adopts a schema; build with the 27.3 SDK to check")]
            }
            return [r("app", .fail, "none of its \(inv.intents.count) intents is a tool intent or adopts a schema, so Siri AI calls none of them")]
        case "intent.tool-not-on-schema":
            let adopters = inv.intents.filter { !$0.schemas.isEmpty }
            guard !adopters.isEmpty else { return [r("app", .pass, "no intent adopts a schema")] }
            guard inv.marksTools else { return [r("app", .skip, "\(adopters.count) intents adopt a schema, and this metadata cannot say which are tools; build with the 27.3 SDK to check")] }
            return adopters.map { i in
                i.isTool == true ? r("intent \(i.identifier)", .fail, "is a tool and adopts \(list(i.schemas)); check the schema's domain") : r("intent \(i.identifier)", .pass, "adopts \(list(i.schemas)) and is not a tool")
            }
        case "intent.shortcuts":
            guard !inv.intents.isEmpty else { return [r("app", .skip, "the app has no intents")] }
            return inv.shortcuts.isEmpty ? [r("app", .fail, "no App Shortcuts, so none of its \(inv.intents.count) intents reaches Siri or Spotlight before setup")]
                : [r("app", .pass, "\(inv.shortcuts.count) App Shortcut\(inv.shortcuts.count == 1 ? "" : "s"): \(list(inv.shortcuts.map { $0.title.isEmpty ? $0.intent : $0.title }))")]
        case "entity.type-name":
            return inv.entities.map { e in
                e.displayName.isEmpty ? r("entity \(e.typeName)", .fail, "has no display name")
                    : e.displayName == e.typeName ? r("entity \(e.typeName)", .fail, "its display name is its type name")
                    : r("entity \(e.typeName)", .pass, "“\(e.displayName)”")
            }
        case "entity.properties":
            return entities.map { e in
                e.properties.isEmpty ? r("entity \(e.typeName)", .fail, "“\(e.displayName)” has no properties")
                    : r("entity \(e.typeName)", .pass, "\(e.properties.count): \(list(e.properties.map { $0.title.isEmpty ? $0.identifier : $0.title }))")
            }
        case "entity.property-description":
            return entities.flatMap { e in
                e.properties.map { p in
                    if let d = p.description { return r("entity \(e.typeName) · \(p.identifier)", .pass, "“\(clip(d))”") }
                    if !inv.isSiriAISDK { return r("entity \(e.typeName) · \(p.identifier)", .skip, "metadata from Xcode tools \(inv.generator ?? "of unknown version"): its @Property takes no description; build with the 27.3 SDK to check") }
                    // The field a 27.3 build writes is not pinned by a fixture yet, so a missing one is not yet the app's failure.
                    if !inv.marksPropertyDescriptions { return r("entity \(e.typeName) · \(p.identifier)", .skip, "metadata from Xcode tools \(inv.generator ?? "?") has no property description ax-xray \(version) recognises; until a 27.3 fixture pins the field, this skips") }
                    return r("entity \(e.typeName) · \(p.identifier)", .fail, "“\(p.title)” has no description")
                }
            }
        case "entity.findable":
            return entities.map { e in
                var ways: [String] = []
                if e.indexed { ways.append("indexed in Spotlight") }
                if e.enumerable { ways.append("its query lists them") }
                if e.stringSearchable { ways.append("its query searches by text") }
                return ways.isEmpty ? r("entity \(e.typeName)", .fail, "is not indexed, and its query neither lists nor searches them") : r("entity \(e.typeName)", .pass, ways.joined(separator: ", "))
            }
        case "entity.transferable":
            return entities.map { e in
                e.exportableTypes.isEmpty ? r("entity \(e.typeName)", .fail, "“\(e.displayName)” is not Transferable") : r("entity \(e.typeName)", .pass, "exports \(list(e.exportableTypes))")
            }
        default:
            return [r("app", .skip, "ax-xray \(version) has no metadata check for this claim")]
        }
    }

    static func skillChecks(_ id: String, _ report: SkillsLint.Report?) -> [R] {
        guard let report, !report.bundles.isEmpty else { return [r("app", .skip, "the app ships no Skills.skillsbundle; app skills are optional")] }
        let codes = skillCodes[id] ?? []
        let findings = report.findings.filter { codes.contains($0.code) }
        if id == "skill.bundle-shape" {
            return report.bundles.map { b in
                let name = URL(fileURLWithPath: b).lastPathComponent
                let mine = findings.filter { $0.path.hasPrefix(b) }
                return mine.isEmpty ? r("skill bundle \(name)", .pass, "\(report.skills.count) skill\(report.skills.count == 1 ? "" : "s")") : r("skill bundle \(name)", .fail, mine.map(\.message).joined(separator: "; "))
            }
        }
        return report.skills.map { s in
            let mine = findings.filter { $0.thing == "Skills/\(s)" || $0.thing.hasPrefix("Skills/\(s)/") }
            return mine.isEmpty ? r("skill \(s)", .pass, "no \(list(codes.sorted())) findings") : r("skill \(s)", .fail, mine.map(\.message).joined(separator: "; "))
        }
    }

    static let behaviourNeeds = "needs a behaviour run: AppIntentsTesting against the app on a device or simulator whose OS matches the Xcode (ouro-ax-xray plan, then the XrayProbe template)"

    /// An error that says the probe never reached the app, which says nothing about the app.
    static func unreachable(_ error: String) -> Bool {
        notPermitted(error) || error.range(of: #"transportCancelled|Failed to resolve actor for key|Underlying session was cancelled|connection (was )?(interrupted|invalidated)|NSCocoaErrorDomain Code=4097|could not (connect|find the app)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The parameter App Intents asked a value for when a reference resolved to nothing (AppIntentsServicesExecutionErrorDomain 206).
    static func askedAgain(_ error: String) -> String? {
        guard let m = error.range(of: #"requested value for parameter '([^']+)'"#, options: .regularExpression) else { return nil }
        return String(error[m]).components(separatedBy: "'").dropFirst().first
    }

    /// AppIntentsTesting refused the probe (AppIntentsServicesSecurityErrorDomain 800), which macOS does when the app
    /// and the test bundle are not signed by one development team.
    static func notPermitted(_ error: String) -> Bool {
        error.range(of: #"executionPermissionDenied|does not have permission to perform this|AppIntentsServicesSecurityErrorDomain"#, options: .regularExpression) != nil
    }

    static func unreachableNote(_ error: String) -> String {
        if notPermitted(error) {
            return "AppIntentsTesting refused the probe (\(clip(error))); sign the app and the probe with one development team and run again"
        }
        return "the probe could not reach the app (\(clip(error))); check that it is running and that the OS matches the Xcode, then run again"
    }

    static func behaviourChecks(_ id: String, _ inv: Inventory, _ probe: ProbeResult?) -> [R] {
        let entities = inv.entities.filter { !$0.transient }
        guard let probe else {
            if id == "intent.error-names-fix" || id == "annotation.onscreen" || !entities.isEmpty { return [r("app", .skip, behaviourNeeds)] }
            return [r("app", .skip, "the app has no entities")]
        }
        func ran(_ e: Inventory.Entity) -> Int? { [probe.step(e.typeName, "suggested")?.count, probe.step(e.typeName, "all")?.count].compactMap { $0 }.max() }
        switch id {
        case "entity.ids-resolve":
            return entities.map { e in
                let s = "entity \(e.typeName)"
                guard let step = probe.step(e.typeName, "identifiers") else { return r(s, .skip, "the probe did not reach this entity") }
                if let error = step.error { return unreachable(error) ? r(s, .skip, unreachableNote(error)) : r(s, .fail, "asking by identifier threw: \(clip(error))") }
                if (step.asked ?? 0) == 0, let cut = [probe.step(e.typeName, "suggested"), probe.step(e.typeName, "all")].compactMap({ $0?.error }).first(where: unreachable) {
                    return r(s, .skip, unreachableNote(cut))
                }
                if (step.asked ?? 0) == 0, let thrown = [probe.step(e.typeName, "suggested"), probe.step(e.typeName, "all")].compactMap({ $0?.error }).first {
                    return r(s, .skip, "could not list any to look up, because listing threw: \(clip(thrown))")
                }
                guard let asked = step.asked, asked > 0 else { return r(s, .skip, "the app suggested none on the test device, so there was nothing to look up; add content and run again") }
                let got = step.count ?? 0
                return got >= asked ? r(s, .pass, "\(got) of \(asked) identifiers resolved") : r(s, .fail, "only \(got) of \(asked) identifiers the query handed out resolved")
            }
        case "entity.indexed":
            return entities.filter(\.indexed).map { e in
                let s = "entity \(e.typeName)"
                guard let step = probe.step(e.typeName, "spotlight") else { return r(s, .skip, "the probe did not reach this entity") }
                if let error = step.error { return unreachable(error) ? r(s, .skip, unreachableNote(error)) : r(s, .fail, "spotlightQuery threw: \(clip(error))") }
                if let n = step.count, n > 0 { return r(s, .pass, "Spotlight holds \(n)") }
                if let n = ran(e), n > 0 { return r(s, .fail, "Spotlight holds none, though its query returns \(n)") }
                return r(s, .skip, "no content of this type on the test device; add some and run again")
            }
        case "entity.transfer-round-trip":
            return entities.filter { !$0.exportableTypes.isEmpty }.map { e in
                let s = "entity \(e.typeName)"
                if let step = probe.step(e.typeName, "export"), !probe.refusalsAllowed { return r(s, .skip, step.note ?? "exported; reading it back waits for a disposable device") }
                if e.importableTypes.isEmpty {
                    if let step = probe.step(e.typeName, "export") { return r(s, .skip, step.note ?? "exported; it imports nothing, so there is nothing to read back") }
                    if let error = probe.step(e.typeName, "export-resolve")?.error { return unreachable(error) ? r(s, .skip, unreachableNote(error)) : r(s, .fail, "export threw: \(clip(error))") }
                    return r(s, .skip, "it exports but imports nothing, so there is nothing to read back")
                }
                guard let step = probe.step(e.typeName, "export-resolve") else { return r(s, .skip, "no content of this type on the test device; add some and run again") }
                if let error = step.error { return unreachable(error) ? r(s, .skip, unreachableNote(error)) : r(s, .fail, clip(error)) }
                return r(s, .pass, step.note ?? "exported and read back")
            }
        case "annotation.onscreen":
            let steps = entities.compactMap { probe.step($0.typeName, "view-annotations") }
            if let bad = steps.first(where: { $0.error.map { !unreachable($0) } ?? false }) { return [r("app", .fail, "viewAnnotations() for \(bad.subject) threw: \(clip(bad.error!))")] }
            if let cut = steps.first(where: { $0.error != nil }), !steps.contains(where: { ($0.count ?? 0) > 0 }) { return [r("app", .skip, unreachableNote(cut.error!))] }
            let shown = steps.filter { ($0.count ?? 0) > 0 }
            if !shown.isEmpty { return [r("app", .pass, "on the launch screen: \(list(shown.map { "\($0.count!) \($0.subject)" }))")] }
            return [r("app", .skip, "no entity is annotated on the launch screen; a person should open a screen that shows entities and run again")]
        case "intent.error-names-fix":
            let steps = probe.steps.filter { $0.probe == "refusal" }
            guard probe.refusalsAllowed else { return [r("app", .skip, "refusal runs are off: they run only on a disposable device (--disposable)")] }
            let tooMany = probe.steps.filter { $0.probe == "refusal-skipped" }
            guard !steps.isEmpty || !tooMany.isEmpty else { return [r("app", .skip, "no intent takes only entity parameters, so none can be given a made-up entity")] }
            if steps.isEmpty { return tooMany.map { r("intent \($0.subject)", .skip, $0.note ?? "the probe gives at most two entities") } }
            return steps.map { step in
                let s = "intent \(step.subject)"
                guard let error = step.error else { return r(s, .fail, "ran with an entity nothing can match; it should be refused") }
                if unreachable(error) { return r(s, .skip, unreachableNote(error)) }
                if let param = askedAgain(error) {
                    return r(s, .skip, "the system asked for ‘\(param)’ again, as Siri asks “which one?”, so the made-up entity never reached the intent and its own error never ran; a person checks this one")
                }
                let (verdict, note) = refusalVerdict(error)
                return r(s, verdict, note)
            }
        default:
            return [r("app", .skip, "ax-xray \(version) has no behaviour check for this claim")]
        }
    }

    /// Whether a refusal's error names what to do next.
    static func refusalVerdict(_ error: String) -> (Verdict, String) {
        let text = error.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return (.fail, "refused with an empty error") }
        if text.range(of: #"(Domain=|Code=|error \d+|\(\w+(\.\w+)+ error \d+\))"#, options: .regularExpression) != nil {
            return (.fail, "refused, but the error shows a domain and code: \(clip(text))")
        }
        let next = #"\b(try|pick|choose|select|open|add|create|check|make sure|sign in|log in|use|go to|tap|connect|enable|turn on|allow|update|ask|search|say)\b"#
        // The verb must open a sentence or clause ("Pick one…", "…, then try again"), so "Could not open it" is not a fix.
        let clause = #"(^|[.;:!?]\s+|,\s*(then|and|or)?\s*|\bthen\s+)"# + next
        if text.range(of: clause, options: [.regularExpression, .caseInsensitive]) != nil || text.range(of: "try again", options: .caseInsensitive) != nil { return (.pass, "“\(clip(text))”") }
        return (.fail, "says what went wrong but not what to do: “\(clip(text))”")
    }

    static let siriNeeds = "needs SiriEvaluations: the app's scenario set, run five times on a 27.3 beta OS on an Apple Intelligence device"

    static func siriChecks(_ id: String, _ siri: SiriResults?) -> [R] {
        guard let siri else { return [r("app", .skip, siriNeeds)] }
        guard let kind = siriKinds[id] else { return [r("app", .skip, "ax-xray \(version) maps no SiriEvaluations expectation to this claim")] }
        let scenarios = siri.scenarios.filter { $0.passes[kind] != nil }
        guard !scenarios.isEmpty else { return [r("app", .skip, "no \(kind) pass rate was recorded: the generated tests record calls and loads, and Xcode's own report grades \(kind)")] }
        return scenarios.map { sc in
            let rate = OuroAXTesting.PassRate(passes: sc.passes[kind]!)
            return r("scenario \(sc.id)", rate.meets(siri.threshold) ? .pass : .fail, "\(kind): \(rate) on \(siri.ranOn), threshold \(Int(siri.threshold * 100))%")
        }
    }

    static func personChecks(_ id: String, _ inv: Inventory) -> [R] {
        let entities = inv.entities.filter { !$0.transient }
        let note: String
        switch id {
        case "intent.confirms-what-others-see":
            let verbs = #"^(Send|Share|Post|Publish|Invite|Reply|Message|Email|Delete|Remove|Replace|Archive|Revoke|Disconnect|Sign Out)"#
            let candidates = inv.intents.filter { $0.title.range(of: verbs, options: .regularExpression) != nil }.map(\.title)
            note = candidates.isEmpty ? "needs a person: run each intent that sends, shares or posts through Siri and Shortcuts and check it asks first; by title, none looks like one"
                : "needs a person: run these through Siri and Shortcuts and check each asks first, if others see or it cannot be undone: \(list(candidates))"
        case "intent.reads-in-shortcuts":
            note = "needs a person: find the app's \(inv.intents.count) intents in the Shortcuts action library and read each summary"
        case "entity.private-properties":
            let props = entities.flatMap { e in e.properties.map { "\(e.displayName).\($0.title.isEmpty ? $0.identifier : $0.title)" } }
            note = props.isEmpty ? "needs a person: no entity exposes properties yet; review each one when it does" : "needs a person: mark any of these that are sensitive or internal: \(list(props))"
        case "entity.display-representation":
            note = entities.isEmpty ? "needs a person: the app has no entities" : "needs a person: find each in Spotlight and Shortcuts and check its title, subtitle and image: \(list(entities.map(\.displayName)))"
        default:
            note = "needs a person on a device"
        }
        return [r("app", .skip, note)]
    }

    static func clip(_ s: String, _ n: Int = 120) -> String {
        let one = s.replacingOccurrences(of: "\n", with: " ")
        return one.count > n ? String(one.prefix(n - 1)) + "…" : one
    }

    static func list(_ items: [String], _ max: Int = 8) -> String {
        items.count > max ? items.prefix(max).joined(separator: ", ") + " and \(items.count - max) more" : items.joined(separator: ", ")
    }
}
