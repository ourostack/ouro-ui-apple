import Foundation
import OuroAXSkillsLint
import Testing
@testable import OuroAXTesting

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func fixtureInventory() throws -> AXXray.Inventory {
    try AXXray.Inventory(actionsData: fixture("fixture-ios.actionsdata.json"))
}

private func verdicts(_ results: [AXXray.CheckResult], _ claim: String) -> [String: AXXray.Verdict] {
    Dictionary(results.filter { $0.claim == claim }.map { ($0.surface, $0.verdict) }, uniquingKeysWith: { a, _ in a })
}

@Suite struct ClaimSetTests {
    @Test func theBundledSetIsCoresAndItsHashMatchesCores() throws {
        let set = try AXXray.ClaimSet.bundled()
        #expect(set.version == "0.1.0")
        #expect(set.claims.count == 30)
        // core: claimSetHash(standard/ax/surfaces/apple.claims.json) at v0.2.0, unchanged in v0.3.0
        #expect(set.hash == "27b3ea5e80b47c18c90c6bf25a832da489dae4a043532d5f23414917d06be9a0")
        #expect(set.claims.allSatisfy { $0.tier == "should" })
    }

    @Test func canonicalJSONIgnoresKeyOrderAndSpacing() throws {
        let a = try AXXray.canonicalJSON(Data(#"{"b": [1, {"d": "x/y", "c": "é"}], "a": true}"#.utf8))
        #expect(String(decoding: a, as: UTF8.self) == #"{"a":true,"b":[1,{"c":"é","d":"x/y"}]}"#)
    }

    // ouro-ui-core's test/fixtures/canonical-json-vector.json: keys sort by UTF-16 code unit, as JavaScript sorts,
    // which JSONSerialization's case-insensitive .sortedKeys does not.
    @Test func canonicalJSONMatchesCoresSharedVector() throws {
        struct Vector: Decodable { var text: String; var sha256: String }
        let data = try fixture("canonical-json-vector.json")
        let vector = try JSONDecoder().decode(Vector.self, from: data)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try JSONSerialization.data(withJSONObject: try #require(object["input"]), options: [.fragmentsAllowed])
        let text = try AXXray.canonicalJSON(input)
        #expect(String(decoding: text, as: UTF8.self) == vector.text)
        #expect(AXXray.sha256Hex(text) == vector.sha256)
        let escapes = try AXXray.canonicalJSON(Data(#"["\u0001\n\t\\", 1e21, -0.25, 3.0]"#.utf8))
        #expect(String(decoding: escapes, as: UTF8.self) == #"["\u0001\n\t\\",1e+21,-0.25,3]"#)
        // node -e 'console.log([1e-7, 1.5e-8, 0.000001, 123.456, 2.5e25].map(String).join(" "))'
        #expect([1e-7, 1.5e-8, 0.000001, 123.456, 2.5e25].map(AXXray.javaScriptNumber) == ["1e-7", "1.5e-8", "0.000001", "123.456", "2.5e+25"])
    }
}

@Suite struct InventoryTests {
    @Test func readsTheFixturesIntentsEntitiesAndShortcuts() throws {
        let inv = try fixtureInventory()
        #expect(inv.generator == "27B52")
        #expect(inv.intents.map(\.identifier) == ["GetNoteBodyIntent", "OpenNoteIntent", "TagNoteIntent"])
        let get = try #require(inv.intents.first { $0.identifier == "GetNoteBodyIntent" })
        #expect(get.title == "Get Note Body")
        #expect(get.description == "Returns the text of a note.")
        #expect(get.parameters.first?.entityType == "NoteEntity")
        #expect(get.parameters.first?.description == "The note to read.")
        #expect(get.isTool == nil)
        #expect(inv.intents.first { $0.identifier == "TagNoteIntent" }?.description == nil)
        let note = try #require(inv.entities.first { $0.typeName == "NoteEntity" })
        #expect(note.displayName == "Note" && note.indexed && note.enumerable && note.stringSearchable)
        #expect(note.exportableTypes == ["public.utf8-plain-text"])
        #expect(note.properties.map(\.identifier) == ["title", "body"])
        let tag = try #require(inv.entities.first { $0.typeName == "TagEntity" })
        #expect(!tag.indexed && !tag.enumerable && !tag.stringSearchable && tag.properties.isEmpty && tag.exportableTypes.isEmpty)
        #expect(inv.shortcuts.map(\.intent) == ["OpenNoteIntent"])
        #expect(!inv.marksTools && !inv.isSiriAISDK)
    }

    @Test func tellsTheSiriAISDKFromTheGenerator() throws {
        func inv(_ g: String) throws -> AXXray.Inventory { try AXXray.Inventory(actionsData: Data(#"{"generator":{"version":"\#(g)"},"actions":{}}"#.utf8)) }
        #expect(try !inv("27A123").isSiriAISDK)
        #expect(try !inv("27B52").isSiriAISDK)
        #expect(try inv("27C5034e").isSiriAISDK)
        #expect(try inv("28A1").isSiriAISDK)
    }
}

@Suite struct MetadataCheckTests {
    let results: [AXXray.CheckResult]
    init() throws { results = AXXray.check(try .bundled(), .init(inventory: try fixtureInventory())) }

    @Test func intentsWithoutDescriptionsFail() {
        let v = verdicts(results, "intent.description")
        #expect(v["intent TagNoteIntent"] == .fail)
        #expect(v["intent OpenNoteIntent"] == .pass)
        #expect(verdicts(results, "intent.parameter-description")["intent TagNoteIntent · tag"] == .fail)
        #expect(verdicts(results, "intent.parameter-description")["intent GetNoteBodyIntent · note"] == .pass)
    }

    @Test func entitiesAreCheckedForNamesPropertiesFindingAndTransfer() {
        #expect(verdicts(results, "entity.type-name") == ["entity NoteEntity": .pass, "entity TagEntity": .fail])
        #expect(verdicts(results, "entity.properties") == ["entity NoteEntity": .pass, "entity TagEntity": .fail])
        #expect(verdicts(results, "entity.findable") == ["entity NoteEntity": .pass, "entity TagEntity": .fail])
        #expect(verdicts(results, "entity.transferable") == ["entity NoteEntity": .pass, "entity TagEntity": .fail])
    }

    @Test func whatXcode272CannotWriteIsSkippedAndSaysSo() throws {
        let tool = try #require(results.first { $0.claim == "intent.tool" })
        #expect(tool.verdict == .skip && tool.note.contains("27B52") && tool.note.contains("27.3"))
        let props = results.filter { $0.claim == "entity.property-description" }
        #expect(props.count == 2 && props.allSatisfy { $0.verdict == .skip && $0.note.contains("27.3") })
    }

    @Test func appShortcutsPass() {
        #expect(verdicts(results, "intent.shortcuts") == ["app": .pass])
    }

    @Test func lanesThatDidNotRunAreSkippedWithWhatWouldRunThem() {
        let open = results.filter { ["entity.ids-resolve", "intent.siri-calls", "entity.display-representation"].contains($0.claim) }
        #expect(open.allSatisfy { $0.verdict == .skip })
        #expect(open.contains { $0.note.contains("AppIntentsTesting") })
        #expect(open.contains { $0.note.contains("SiriEvaluations") && $0.note.contains("27.3") })
        #expect(open.contains { $0.note.hasPrefix("needs a person") && $0.note.contains("Note") })
    }

    @Test func toolIntentsAreCheckedOnceTheMetadataCanMarkThem() throws {
        let json = #"{"generator":{"version":"27C1"},"actions":{"A":{"identifier":"A","title":{"key":"Add"},"parameters":[],"isToolIntent":true},"B":{"identifier":"B","title":{"key":"Bee"},"parameters":[]}}}"#
        let inv = try AXXray.Inventory(actionsData: Data(json.utf8))
        #expect(inv.marksTools)
        #expect(AXXray.metadataChecks("intent.tool", inv).first?.verdict == .pass)
        let none = try AXXray.Inventory(actionsData: Data(#"{"generator":{"version":"27C1"},"actions":{"B":{"identifier":"B","title":{"key":"Bee"},"parameters":[]}}}"#.utf8))
        // 27.3 metadata with no marker this checker knows: the checker's gap, so a skip.
        #expect(AXXray.metadataChecks("intent.tool", none).first?.verdict == .skip)
        #expect(AXXray.metadataChecks("intent.tool", none).first?.note.contains("no tool marker") == true)
        let marked = try AXXray.Inventory(actionsData: Data(#"{"generator":{"version":"27C1"},"actions":{"B":{"identifier":"B","title":{"key":"Bee"},"parameters":[],"isToolIntent":false}}}"#.utf8))
        #expect(AXXray.metadataChecks("intent.tool", marked).first?.verdict == .fail)
        #expect(AXXray.metadataChecks("entity.property-description", marked).isEmpty)
    }
}

@Suite struct SkillCheckTests {
    @Test func linterFindingsMapToTheirClaims() throws {
        let report = SkillsLint.Report(ok: false, summary: "", bundles: ["/x/Skills.skillsbundle"], skills: ["plan-dinner", "Bad"], findings: [
            .init(severity: .error, code: "skill-name", thing: "Skills/Bad", problem: "a skill's folder name has only lowercase letters", fix: "rename it", path: "/x/Skills.skillsbundle/Skills/Bad"),
            .init(severity: .error, code: "body-too-long", thing: "Skills/plan-dinner/SKILL.md", problem: "is too long", fix: "cut it", path: "/x/Skills.skillsbundle/Skills/plan-dinner/SKILL.md"),
        ], exitCode: 3)
        let results = AXXray.check(try .bundled(), .init(inventory: try fixtureInventory(), skills: report))
        #expect(verdicts(results, "skill.names") == ["skill plan-dinner": .pass, "skill Bad": .fail])
        #expect(verdicts(results, "skill.body") == ["skill plan-dinner": .fail, "skill Bad": .pass])
        #expect(verdicts(results, "skill.bundle-shape") == ["skill bundle Skills.skillsbundle": .pass])
    }

    @Test func noSkillsBundleIsASkipNotAFailure() throws {
        let results = AXXray.check(try .bundled(), .init(inventory: try fixtureInventory()))
        #expect(results.filter { $0.claim.hasPrefix("skill.") && $0.claim != "skill.loads" }.allSatisfy { $0.verdict == .skip && $0.note.contains("optional") })
    }
}

@Suite struct BehaviourCheckTests {
    func probe(_ steps: [AXXray.ProbeResult.Step], refusals: Bool = true) -> AXXray.ProbeResult {
        .init(bundleIdentifier: "bot.ouro.ax.xray-fixture", ranOn: "iOS 27.1 Simulator", refusalsAllowed: refusals, steps: steps)
    }

    @Test func thePlanReadsEveryEntityAndRefusesOnlyIntentsThatTakeOnlyEntities() throws {
        let plan = AXXray.ProbePlan(bundleIdentifier: "b", inventory: try fixtureInventory(), refusals: true)
        #expect(plan.entities.map(\.typeName) == ["NoteEntity", "TagEntity"])
        #expect(plan.refusals.map(\.intent) == ["GetNoteBodyIntent", "OpenNoteIntent", "TagNoteIntent"])
        #expect(plan.refusals.first?.entityParameters == ["note": "NoteEntity"])
        #expect(AXXray.ProbePlan(bundleIdentifier: "b", inventory: try fixtureInventory(), refusals: false).refusals.isEmpty)
    }

    // Seen on macOS 27.0.1 in CI: every call came back "transport cancelled", which is the probe's failure, not the app's.
    @Test func anErrorThatNeverReachedTheAppSkips() throws {
        let cut = "Underlying session was cancelled. (transportCancelled(message: \"(transport cancelled)\"))"
        let p = probe([
            .init(subject: "NoteEntity", probe: "identifiers", error: "The distributed invocation was not executed. Failed to resolve actor for key preset_18AppIntentsServices37$RunnerServiceDispatcherActorProtocolC"),
            .init(subject: "TagEntity", probe: "suggested", error: "Your app does not have permission to perform this. Request Bundle ID: b"),
            .init(subject: "TagEntity", probe: "identifiers", count: 0, asked: 0),
            .init(subject: "NoteEntity", probe: "spotlight", error: "Your app does not have permission to perform this. Request Bundle ID: bot.ouro.ax.xray-fixture"),
            .init(subject: "NoteEntity", probe: "view-annotations", error: cut),
            .init(subject: "OpenNoteIntent", probe: "refusal", error: cut),
        ])
        let results = AXXray.check(try .bundled(), .init(inventory: try fixtureInventory(), probe: p))
        #expect(verdicts(results, "entity.ids-resolve")["entity NoteEntity"] == .skip)
        #expect(verdicts(results, "entity.indexed") == ["entity NoteEntity": .skip])
        #expect(verdicts(results, "annotation.onscreen") == ["app": .skip])
        #expect(verdicts(results, "intent.error-names-fix") == ["intent OpenNoteIntent": .skip])
        #expect(results.first { $0.claim == "entity.indexed" }?.note.hasPrefix("AppIntentsTesting refused the probe") == true)
        #expect(results.first { $0.claim == "entity.ids-resolve" }?.note.hasPrefix("the probe could not reach the app") == true)
        #expect(results.first { $0.claim == "entity.ids-resolve" && $0.surface == "entity TagEntity" }?.note.hasPrefix("AppIntentsTesting refused the probe") == true)
        let report = AXXray.report(try .bundled(), .init(inventory: try fixtureInventory(), probe: p), name: "F", bundleIdentifier: "b", platform: "macOS", commit: "c", at: Date(timeIntervalSince1970: 0))
        #expect(report.effects.map(\.note) == ["tried; the call never reached the app"])
    }

    // Seen on the iOS 27.0 and 27.1 simulators in CI.
    @Test func whatTheSystemDoesBeforeTheAppIsNotTheAppsFailure() throws {
        let asked = "Unsupported operation: The App Intent requested value for parameter 'note', which is not supported by AutoConfirmingPerformDelegate"
        let p = probe([
            .init(subject: "NoteEntity", probe: "export", note: "exported n1 as public.utf8-plain-text; it imports nothing, so there is nothing to read back"),
            .init(subject: "OpenNoteIntent", probe: "refusal", error: asked),
        ])
        var inv = try fixtureInventory()
        #expect(inv.entities.first { $0.typeName == "NoteEntity" }?.importableTypes == ["public.utf8-plain-text"])
        #expect(AXXray.ProbePlan(bundleIdentifier: "b", inventory: inv, refusals: true).entities.first?.importable == true)
        // The same entity, exporting only.
        inv.entities[0].importableTypes = []
        let plan = AXXray.ProbePlan(bundleIdentifier: "b", inventory: inv, refusals: true)
        #expect(plan.entities.first?.exportType == "public.utf8-plain-text" && plan.entities.first?.importable == false)
        let results = AXXray.check(try .bundled(), .init(inventory: inv, probe: p))
        #expect(verdicts(results, "entity.transfer-round-trip") == ["entity NoteEntity": .skip])
        #expect(verdicts(results, "intent.error-names-fix") == ["intent OpenNoteIntent": .skip])
        #expect(results.first { $0.claim == "intent.error-names-fix" }?.note.contains("asked for ‘note’ again") == true)
        #expect(AXXray.askedAgain(asked) == "note")
        let report = AXXray.report(try .bundled(), .init(inventory: inv, probe: p), name: "F", bundleIdentifier: "b", platform: "iOS", commit: "c", at: Date(timeIntervalSince1970: 0))
        #expect(report.effects.map(\.note) == ["tried; the system asked for the value again, so the intent never ran"])
    }

    @Test func readingAnExportBackIsAWriteAndWaitsForADisposableDevice() throws {
        let off = probe([.init(subject: "NoteEntity", probe: "export", note: "exported n1; reading it back runs the app's import, so it waits for a disposable device")], refusals: false)
        let results = AXXray.check(try .bundled(), .init(inventory: try fixtureInventory(), probe: off))
        #expect(verdicts(results, "entity.transfer-round-trip") == ["entity NoteEntity": .skip])
        let quiet = AXXray.report(try .bundled(), .init(inventory: try fixtureInventory(), probe: off), name: "F", bundleIdentifier: "b", platform: "iOS", commit: "c", at: Date(timeIntervalSince1970: 0))
        #expect(quiet.safety.checks.first { $0.name == "reads only" }?.ok == true && quiet.effects.isEmpty)
        let on = probe([.init(subject: "NoteEntity", probe: "export-resolve", note: "exported and read back")])
        let busy = AXXray.report(try .bundled(), .init(inventory: try fixtureInventory(), probe: on), name: "F", bundleIdentifier: "b", platform: "iOS", commit: "c", at: Date(timeIntervalSince1970: 0))
        #expect(busy.safety.checks.first { $0.name == "reads only" }?.ok == false)
        #expect(busy.effects.map(\.surface) == ["entity NoteEntity"])
    }

    @Test func resultsBecomeVerdicts() throws {
        let p = probe([
            .init(subject: "NoteEntity", probe: "suggested", count: 3),
            .init(subject: "NoteEntity", probe: "identifiers", count: 3, asked: 3),
            .init(subject: "NoteEntity", probe: "spotlight", count: 0),
            .init(subject: "NoteEntity", probe: "export-resolve", note: "exported as public.utf8-plain-text and read back"),
            .init(subject: "NoteEntity", probe: "view-annotations", count: 3),
            .init(subject: "TagEntity", probe: "suggested", count: 0),
            .init(subject: "TagEntity", probe: "identifiers", count: 0, asked: 0),
            .init(subject: "OpenNoteIntent", probe: "refusal", error: "There's no such note. Pick one from the notes list, then try again."),
            .init(subject: "TagNoteIntent", probe: "refusal", error: "Tag not found."),
            .init(subject: "GetNoteBodyIntent", probe: "refusal", error: "The operation couldn’t be completed. (XrayFixture.FixtureError error 0.)"),
        ])
        let results = AXXray.check(try .bundled(), .init(inventory: try fixtureInventory(), probe: p))
        #expect(verdicts(results, "entity.ids-resolve") == ["entity NoteEntity": .pass, "entity TagEntity": .skip])
        #expect(verdicts(results, "entity.indexed") == ["entity NoteEntity": .fail])
        #expect(verdicts(results, "entity.transfer-round-trip") == ["entity NoteEntity": .pass])
        #expect(verdicts(results, "annotation.onscreen") == ["app": .pass])
        #expect(verdicts(results, "intent.error-names-fix") == ["intent OpenNoteIntent": .pass, "intent TagNoteIntent": .fail, "intent GetNoteBodyIntent": .fail])
    }

    @Test func anIntentThatRunsWithAMadeUpEntityFails() throws {
        let results = AXXray.check(try .bundled(), .init(inventory: try fixtureInventory(), probe: probe([.init(subject: "OpenNoteIntent", probe: "refusal")])))
        #expect(verdicts(results, "intent.error-names-fix") == ["intent OpenNoteIntent": .fail])
    }

    @Test func refusalsAreOffUnlessTheDeviceIsDisposable() throws {
        let results = AXXray.check(try .bundled(), .init(inventory: try fixtureInventory(), probe: probe([], refusals: false)))
        #expect(results.first { $0.claim == "intent.error-names-fix" }?.note.contains("disposable") == true)
    }

    @Test func aProbeResultSurvivesATestLog() throws {
        let p = probe([.init(subject: "NoteEntity", probe: "all", count: 3)])
        let log = "Test Suite started\n\(try p.logLines())\nTest Suite passed\n"
        #expect(try AXXray.ProbeResult.fromLog(log) == p)
        #expect(try AXXray.ProbeResult.fromLog("nothing here") == nil)
    }
}

@Suite struct ReportTests {
    func report(_ evidence: AXXray.Evidence) throws -> AXXray.Report {
        try AXXray.report(.bundled(), evidence, name: "XrayFixture", bundleIdentifier: "bot.ouro.ax.xray-fixture", platform: "iOS", commit: "abc1234", at: Date(timeIntervalSince1970: 0))
    }

    @Test func pinsTheClaimSetAndTheCommitAndSaysWhatItDoesNotProve() throws {
        let r = try report(.init(inventory: try fixtureInventory()))
        #expect(r.tool == "ax-xray" && r.checker.platform == "apple")
        #expect(r.claimSet.hash == (try AXXray.ClaimSet.bundled()).hash)
        #expect(r.target.commit == "abc1234" && r.target.app.intents == 3 && r.target.app.metadataGenerator == "27B52")
        #expect(r.inventory.given && r.inventory.surfaces == ["app-intent", "app-entity"])
        #expect(r.conformant && r.summary.must == 0)
        #expect(r.summary.checks.fail > 0)
        #expect(r.coverage.statement.contains("does not prove what Siri will do"))
        #expect(r.coverage.needsPerson.count == 4)
        #expect(r.coverage.needsSiriEvaluations.count == 5)
        #expect(r.coverage.provedByAppIntentsTesting.isEmpty)
        #expect(r.verdictLine.contains("no must claims"))
    }

    @Test func anAppWithNoMetadataIsTheBaseline() throws {
        let r = try report(.init(inventory: nil))
        #expect(!r.inventory.given && !r.conformant)
        #expect(r.verdictLine.contains("no App Intents metadata"))
        #expect(r.summary.checks.pass == 0)
    }

    @Test func rendersMarkdownHTMLAndJSON() throws {
        let r = try report(.init(inventory: try fixtureInventory()))
        let md = r.markdown()
        #expect(md.hasPrefix("# AX X-ray: XrayFixture\n"))
        #expect(md.contains("## What this proves") && md.contains("## What fails, and the fix") && md.contains("## Open: what needs SiriEvaluations or a person"))
        #expect(md.contains("intent TagNoteIntent"))
        let html = r.html()
        #expect(html.contains("<title>AX X-ray: XrayFixture</title>") && html.contains("prefers-color-scheme:dark") && !html.contains("<script"))
        let back = try JSONDecoder().decode(AXXray.Report.self, from: r.json())
        #expect(back == r)
        #expect(r.text().contains("✗ entity.type-name"))
    }
}

@Suite struct SiriScenarioSetTests {
    let set = AXXray.SiriScenarioSet(app: "XrayFixture", bundleIdentifier: "bot.ouro.ax.xray-fixture", threshold: 0.8, runs: 5, scenarios: [
        .init(id: "open-direct", kind: .direct, turns: ["Open my groceries note in XrayFixture"], calls: [.init(intent: "OpenNoteIntent", parameters: ["note": .init(entity: "NoteEntity", identifier: "groceries")])], needs: "a note named Groceries"),
        .init(id: "read-indirect", kind: .indirect, turns: ["What did I write about groceries?"], calls: [.init(intent: "GetNoteBodyIntent")], finds: ["NoteEntity"], response: "milk"),
        .init(id: "tag-incomplete", kind: .incomplete, turns: ["Tag a note in XrayFixture", "Groceries"], calls: [.init(intent: "TagNoteIntent")]),
        .init(id: "delete-unexpected", kind: .unexpected, turns: ["Delete all my notes in XrayFixture"], disallowed: ["TagNoteIntent", "OpenNoteIntent"]),
    ])

    @Test func checksTheSetAgainstTheAppsMetadata() throws {
        #expect(set.problems(against: try fixtureInventory()).isEmpty)
        var bad = set
        bad.scenarios[0].calls = [.init(intent: "DeleteNoteIntent")]
        bad.scenarios[1].calls = [.init(intent: "GetNoteBodyIntent", parameters: ["note": .init(entity: "TagEntity")])]
        bad.scenarios.removeLast()
        let problems = bad.problems(against: try fixtureInventory())
        #expect(problems.contains("open-direct: calls DeleteNoteIntent, which the app does not have"))
        #expect(problems.contains("read-indirect: GetNoteBodyIntent.note takes NoteEntity, not TagEntity"))
        #expect(problems.contains("no unexpected scenario"))
    }

    @Test func generatesAGuardedTestFile() {
        let swift = set.swiftSource()
        #expect(swift.hasPrefix("// Generated by ouro-ax-xray"))
        #expect(swift.contains("#if canImport(SiriEvaluations)") && swift.hasSuffix("#endif\n"))
        #expect(swift.contains("private let openNoteIntent = app.intents[\"OpenNoteIntent\"]"))
        #expect(swift.contains("openNoteIntent.expect(note: noteEntity.expectIdentifier(\"groceries\"))"))
        #expect(swift.contains("Calls(.disallowed) {"))
        #expect(swift.contains("SiriResponse(.contains(\"milk\"))"))
        #expect(swift.contains("UserTurn(\"Tag a note in XrayFixture\")\n"))
        #expect(swift.contains("func deleteUnexpected() async throws"))
    }

    @Test func readsTheRunsTheGeneratedTestsRecord() throws {
        let lines = #"{"id":"open-direct","passes":{"calls":true}}"# + "\n" + #"{"id":"open-direct","passes":{"calls":false}}"# + "\n"
        let siri = try AXXray.siriResults(jsonLines: lines, ranOn: "iOS 27.3 beta", threshold: 0.8)
        #expect(siri.scenarios.first?.passes["calls"] == [true, false])
        let results = AXXray.check(try .bundled(), .init(inventory: try fixtureInventory(), siri: siri))
        #expect(verdicts(results, "intent.siri-calls") == ["scenario open-direct": .fail])
    }
}

@Suite struct XrayCLITests {
    /// A minimal built iOS app: Info.plist, and the fixture's metadata when `metadata` is on.
    func app(metadata: Bool) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ouro-ax-xray-\(UUID().uuidString)/Fixture.app")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Metadata.appintents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "bot.ouro.ax.xray-fixture", "CFBundleName": "XrayFixture", "CFBundleSupportedPlatforms": ["iPhoneSimulator"]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: dir.appendingPathComponent("Info.plist"))
        if metadata { try fixture("fixture-ios.actionsdata.json").write(to: dir.appendingPathComponent("Metadata.appintents/extract.actionsdata")) }
        return dir
    }

    @Test func aMisspeltFlagIsAUsageError() throws {
        let a = try app(metadata: true).path
        let run = XrayCLI.run(["--app", a, "--conformence"])
        #expect(run.code == 2 && run.stderr.contains("unknown argument --conformence"))
        #expect(XrayCLI.run(["--app", a, "--format", "yaml"]).code == 2)
        #expect(XrayCLI.run(["--app", a, "--conformance", "--format", "json"]).code == 0)
    }

    @Test func aRefusalPassesOnlyWhenItSaysWhatToDo() {
        #expect(AXXray.refusalVerdict("Could not open the note.").0 == .fail)
        #expect(AXXray.refusalVerdict("There's no such note. Pick one from your notes.").0 == .pass)
        #expect(AXXray.refusalVerdict("That note is gone, so try again with another.").0 == .pass)
        #expect(AXXray.refusalVerdict("Sign in to Spoonjoy first.").0 == .pass)
    }

    @Test func helpAndUsage() {
        #expect(XrayCLI.run(["--help"]).stdout.contains("ouro-ax-xray --app <path.app>"))
        let missing = XrayCLI.run(["--format", "json"])
        #expect(missing.code == 2 && missing.stderr.contains("--app <path.app> is required"))
    }

    @Test func reportsFromTheBuiltAppAndWritesAllThreeFormats() throws {
        let a = try app(metadata: true)
        let out = a.deletingLastPathComponent().appendingPathComponent("report")
        let run = XrayCLI.run(["--app", a.path, "--commit", "abc1234", "--format", "json", "--out", out.path])
        #expect(run.code == 0, "\(run.stderr)")
        let report = try JSONDecoder().decode(AXXray.Report.self, from: Data(run.stdout.utf8))
        #expect(report.target.app.bundleIdentifier == "bot.ouro.ax.xray-fixture" && report.target.app.platform == "iOS Simulator" && report.target.commit == "abc1234")
        for f in ["report.json", "report.md", "report.html"] { #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent(f).path)) }
    }

    @Test func anAppWithoutMetadataIsReportedNotRefused() throws {
        let run = XrayCLI.run(["--app", try app(metadata: false).path, "--conformance"])
        #expect(run.code == 1)
        #expect(run.stdout.contains("no App Intents metadata"))
    }

    @Test func planIsBase64JSONAndMergesBack() throws {
        let a = try app(metadata: true)
        let run = XrayCLI.run(["plan", "--app", a.path, "--disposable"])
        let plan = try JSONDecoder().decode(AXXray.ProbePlan.self, from: try #require(Data(base64Encoded: run.stdout.trimmingCharacters(in: .whitespacesAndNewlines))))
        #expect(plan.refusals.count == 3)
        let log = a.deletingLastPathComponent().appendingPathComponent("probe.log")
        try AXXray.ProbeResult(bundleIdentifier: "elsewhere", ranOn: "x", refusalsAllowed: false, steps: []).logLines().write(to: log, atomically: true, encoding: .utf8)
        #expect(XrayCLI.run(["--app", a.path, "--probe", log.path]).stderr.contains("the probe ran against elsewhere"))
    }
}
