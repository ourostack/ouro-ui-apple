import Foundation
import OuroAXSkillsLint
import Testing

/// Writes a bundle into a fresh temporary folder: `files` maps a path inside the bundle to its contents.
private func bundle(_ files: [String: String], name: String = "Skills.skillsbundle") throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ouro-ax-skills-tests-\(UUID().uuidString)")
    let url = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.appendingPathComponent("Skills"), withIntermediateDirectories: true)
    for (path, contents) in files {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file)
    }
    return url
}

private func skill(_ name: String, description: String = "Does one thing well.", body: String = "Use the search tool, then the add tool.", extra: String = "") -> String {
    "---\nname: \(name)\ndescription: \(description)\n\(extra)---\n\(body)\n"
}

private func fixture(_ name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
}

private func codes(_ report: SkillsLint.Report) -> [String] { report.findings.map(\.code) }

@Suite struct SkillsLintRules {
    @Test func aWellFormedBundlePasses() throws {
        let report = try SkillsLint.lint([fixture("Good.skillsbundle")])
        #expect(report.findings.isEmpty)
        #expect(report.skills == ["add-to-list", "cook-along"])
        #expect(report.ok)
        #expect(report.exitCode == 0)
    }

    @Test func skillNamesAreLowercaseLettersNumbersAndHyphens() throws {
        let report = try SkillsLint.lint([bundle(["Skills/Cook_Along/SKILL.md": skill("Cook_Along")])])
        #expect(codes(report).contains("skill-name"))
        let finding = try #require(report.findings.first { $0.code == "skill-name" })
        #expect(finding.severity == .error)
        #expect(finding.fix == "rename the folder to cook-along")
    }

    @Test func eachSkillFolderHoldsOnlySKILLmd() throws {
        let report = try SkillsLint.lint([bundle([
            "Skills/plan/SKILL.md": skill("plan"),
            "Skills/plan/notes.txt": "x",
            "Skills/README.md": "x",
            "Info.plist": "x",
        ])])
        #expect(codes(report).filter { $0 == "stray-file" }.count == 3)
        #expect(report.exitCode == 3)
    }

    @Test func aSkillFolderNeedsSKILLmd() throws {
        let report = try SkillsLint.lint([bundle(["Skills/plan/skill.md": skill("plan")])])
        #expect(codes(report).contains("skill-md-missing"))
    }

    @Test func theBundleNeedsASkillsFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ouro-ax-skills-tests-\(UUID().uuidString)/Skills.skillsbundle")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(codes(try SkillsLint.lint([root])) == ["skills-folder-missing"])
    }

    @Test func frontmatterHoldsOnlyNameAndDescription() throws {
        let report = try SkillsLint.lint([bundle([
            "Skills/a/SKILL.md": skill("a", extra: "license: MIT\nallowed-tools: search\n"),
            "Skills/b/SKILL.md": "No frontmatter at all.\n",
            "Skills/c/SKILL.md": "---\nname: c\n---\nBody.\n",
        ])])
        #expect(codes(report).filter { $0 == "frontmatter-field" }.count == 2)
        #expect(codes(report).contains("frontmatter-missing"))
        #expect(codes(report).contains("description-missing"))
        let license = try #require(report.findings.first { $0.code == "frontmatter-field" })
        #expect(license.line == 4)
    }

    @Test func theBodyIsAtMostTenThousandCharacters() throws {
        let fits = String(repeating: "é", count: 10_000)
        #expect(try SkillsLint.lint([bundle(["Skills/a/SKILL.md": skill("a", body: fits)])]).findings.isEmpty)
        let report = try SkillsLint.lint([bundle(["Skills/a/SKILL.md": skill("a", body: fits + "x")])])
        #expect(codes(report) == ["body-too-long"])
        #expect(report.findings[0].problem.contains("10001"))
    }

    @Test func namesAreUniqueAcrossBundles() throws {
        let app = try bundle(["Skills/plan/SKILL.md": skill("plan")])
        let widget = try bundle(["Skills/plan/SKILL.md": skill("plan")])
        let report = try SkillsLint.lint([app, widget])
        #expect(codes(report) == ["duplicate-name"])
        #expect(report.findings[0].severity == .error)
    }

    @Test func theBodyRefersToToolsInformally() throws {
        let report = try SkillsLint.lint([bundle(["Skills/a/SKILL.md": skill("a", body: "Call StartCookModeIntent, then the next step tool.")])])
        #expect(codes(report) == ["intent-type-name"])
        #expect(report.findings[0].severity == .warning)
        #expect(report.exitCode == 0)
        #expect(try SkillsLint.lint([bundle(["Skills/a/SKILL.md": skill("a", body: "Call StartCookModeIntent.")])], strict: true).exitCode == 3)
    }

    @Test func theFrontmatterNameMatchesItsFolder() throws {
        let report = try SkillsLint.lint([bundle(["Skills/plan/SKILL.md": skill("plan-trip")])])
        #expect(codes(report) == ["name-mismatch"])
        #expect(report.findings[0].severity == .warning)
    }

    @Test func aPathThatIsNotABundleIsAUsageError() throws {
        #expect(throws: SkillsLint.UsageError.self) { try SkillsLint.lint([URL(fileURLWithPath: "/nonexistent/Skills.skillsbundle")]) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ouro-ax-skills-tests-\(UUID().uuidString).md")
        try Data("x".utf8).write(to: file)
        #expect(throws: SkillsLint.UsageError.self) { try SkillsLint.lint([file]) }
    }

    @Test func theBadFixtureFindsEveryKind() throws {
        let report = try SkillsLint.lint([fixture("Bad.skillsbundle")])
        #expect(Set(codes(report)) == ["skill-name", "intent-type-name", "frontmatter-field", "stray-file", "body-too-long", "name-mismatch"])
        #expect(report.exitCode == 3)
    }
}

@Suite struct SkillsCLITests {
    @Test func jsonUsesTheProblemShapeAndTheFindingsExit() throws {
        let run = SkillsCLI.run(["lint", try fixture("Bad.skillsbundle").path, "--json"])
        #expect(run.code == 3)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any])
        #expect(object["ax"] as? String == "skills-lint/1")
        #expect(object["exitCode"] as? Int == 3)
        let first = try #require((object["findings"] as? [[String: Any]])?.first)
        for key in ["code", "exit", "thing", "problem", "fix", "message", "severity", "path"] { #expect(first[key] != nil, "\(key)") }
        #expect(first["exit"] as? Int == 3)
    }

    @Test func textLeadsWithTheVerdict() throws {
        let ok = SkillsCLI.run(["lint", try fixture("Good.skillsbundle").path])
        #expect(ok.code == 0)
        #expect(ok.stdout.hasPrefix("ok: 2 skills in 1 bundle, no findings."))
        let bad = SkillsCLI.run(["lint", try fixture("Bad.skillsbundle").path])
        #expect(bad.stdout.hasPrefix("findings:"))
        #expect(bad.stdout.contains("Fix: rename the folder to cook-along."))
    }

    @Test func xcodeFormatPointsAtTheLine() throws {
        let run = SkillsCLI.run(["lint", try fixture("Bad.skillsbundle").path, "--format", "xcode"])
        #expect(run.stdout.split(separator: "\n").contains { $0.contains("shopping-run/SKILL.md:4: error: ") })
        #expect(run.stdout.contains(": warning: "))
    }

    @Test func usageErrorsExitTwoWithTheFix() {
        let none = SkillsCLI.run([])
        #expect(none.code == 2)
        #expect(none.stderr.hasPrefix("ouro-ax-skills: lint: needs a bundle path."))
        let typo = SkillsCLI.run(["lnt", "x"])
        #expect(typo.code == 2)
        #expect(typo.stderr.contains("Fix: ouro-ax-skills lint x."))
        let flag = SkillsCLI.run(["lint", "x", "--jsn"])
        #expect(flag.code == 2)
        #expect(flag.stderr.contains("--json"))
        let missing = SkillsCLI.run(["lint", "/nonexistent/Skills.skillsbundle", "--json"])
        #expect(missing.code == 2)
        let error = (try? JSONSerialization.jsonObject(with: Data(missing.stdout.utf8))) as? [String: Any]
        #expect((error?["error"] as? [String: Any])?["code"] as? String == "no-bundle")
    }

    @Test func helpListsTheExitCodes() {
        let help = SkillsCLI.run(["--help"])
        #expect(help.code == 0)
        #expect(help.stdout.contains("Exit codes: 0 ok, 1 error, 2 usage, 3 findings."))
    }
}

@Suite struct SkillsStampTests {
    @Test func theStampIsWrittenOnlyWhenTheLintPasses() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ouro-ax-skills-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let good = folder.appendingPathComponent("good.stamp")
        let bad = folder.appendingPathComponent("bad.stamp")
        #expect(SkillsCLI.run(["lint", try fixture("Good.skillsbundle").path, "--stamp", good.path]).code == 0)
        #expect(FileManager.default.fileExists(atPath: good.path))
        #expect(SkillsCLI.run(["lint", try fixture("Bad.skillsbundle").path, "--stamp", bad.path]).code == 3)
        #expect(!FileManager.default.fileExists(atPath: bad.path))
    }
}
