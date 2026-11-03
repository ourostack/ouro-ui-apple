public import Foundation
public import OuroAX

/// Lints app-skills bundles (`Skills.skillsbundle`) against the rules in Apple's "Orchestrating complex actions with
/// app skills" (Siri AI Developer Preview, 2026-11-03) and Ouro AX's `app-skill` claims:
///
/// - one `Skills/` folder; each skill is `Skills/<name>/SKILL.md` and nothing else is in the bundle;
/// - a skill's folder name has only lowercase letters, numbers and hyphens, and is unique across every bundle linted;
/// - `SKILL.md` starts with frontmatter holding only `name` and `description`, both present;
/// - the body is at most 10,000 characters;
/// - (warnings) the frontmatter name matches the folder, the body is not empty, and the body names tools informally
///   ("the search tool"), never by intent type name.
public enum SkillsLint {
    public static let version = "skills-lint/1"
    public static let maximumBodyCharacters = 10_000
    public static let exits = try! OuroAX.ExitTable(OuroAX.ExitCode.base + [OuroAX.ExitCode.findings])

    public enum Severity: String, Codable, Sendable, Hashable {
        case error
        case warning
    }

    /// One finding: an `ax-problem` (code, exit, thing, problem, fix, message) plus where it is and how much it matters.
    public struct Finding: Codable, Sendable, Hashable {
        public var severity: Severity
        public var code: String
        public var thing: String
        public var problem: String
        public var fix: String?
        /// The file or folder, as given on the command line plus the path inside the bundle.
        public var path: String
        /// The 1-based line in `SKILL.md`, when the finding has one.
        public var line: Int?
        /// The exit code this finding causes: 3 for an error, 0 for a warning (3 under `--strict`).
        public var exit: Int

        public var asProblem: OuroAX.Problem {
            .init(code: code, exit: exit, thing: thing, problem: problem, fix: fix)
        }

        public var message: String { asProblem.message }

        private enum CodingKeys: String, CodingKey { case code, exit, thing, problem, fix, message, severity, path, line }

        public init(severity: Severity, code: String, thing: String, problem: String, fix: String?, path: String, line: Int? = nil) {
            self.severity = severity
            self.code = code
            self.thing = thing
            self.problem = problem
            self.fix = fix
            self.path = path
            self.line = line
            exit = severity == .error ? OuroAX.ExitCode.findings.code : 0
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            severity = try c.decode(Severity.self, forKey: .severity)
            code = try c.decode(String.self, forKey: .code)
            thing = try c.decode(String.self, forKey: .thing)
            problem = try c.decode(String.self, forKey: .problem)
            fix = try c.decodeIfPresent(String.self, forKey: .fix)
            path = try c.decode(String.self, forKey: .path)
            line = try c.decodeIfPresent(Int.self, forKey: .line)
            exit = try c.decode(Int.self, forKey: .exit)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(code, forKey: .code)
            try c.encode(asProblem.exit, forKey: .exit)
            try c.encode(thing, forKey: .thing)
            try c.encode(problem, forKey: .problem)
            if let fix { try c.encode(fix, forKey: .fix) } else { try c.encodeNil(forKey: .fix) }
            try c.encode(message, forKey: .message)
            try c.encode(severity, forKey: .severity)
            try c.encode(path, forKey: .path)
            if let line { try c.encode(line, forKey: .line) } else { try c.encodeNil(forKey: .line) }
        }
    }

    /// One run's facts, the same for a person's text and an agent's `--json`.
    public struct Report: Codable, Sendable, Hashable {
        public var ax: String = SkillsLint.version
        public var ok: Bool
        public var summary: String
        public var bundles: [String]
        public var skills: [String]
        public var findings: [Finding]
        public var exitCode: Int

        public init(ok: Bool, summary: String, bundles: [String], skills: [String], findings: [Finding], exitCode: Int) {
            self.ok = ok
            self.summary = summary
            self.bundles = bundles
            self.skills = skills
            self.findings = findings
            self.exitCode = exitCode
        }
    }

    /// A path that is not a skills bundle: nothing was linted (exit 2).
    public struct UsageError: Error, Sendable {
        public let problem: OuroAX.Problem
    }

    static let allowedFields: Set<String> = ["name", "description"]

    /// Lints each bundle and the names across all of them. `strict` counts warnings as findings for the exit code.
    public static func lint(_ bundles: [URL], strict: Bool = false) throws -> Report {
        var findings: [Finding] = []
        var skills: [String] = []
        var seen: [String: String] = [:]
        for bundle in bundles {
            let bundlePath = bundle.path
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: bundlePath, isDirectory: &isDirectory) else {
                throw UsageError(problem: .init(code: "no-bundle", exit: 2, thing: bundlePath, problem: "no such file or folder", fix: "pass the path of a Skills.skillsbundle folder"))
            }
            guard isDirectory.boolValue, bundle.pathExtension == "skillsbundle" else {
                throw UsageError(problem: .init(code: "not-a-bundle", exit: 2, thing: bundlePath, problem: "is not a .skillsbundle folder", fix: "pass the Skills.skillsbundle folder that Xcode added to the target"))
            }
            if bundle.lastPathComponent != "Skills.skillsbundle" {
                findings.append(.init(severity: .warning, code: "bundle-name", thing: bundle.lastPathComponent, problem: "Siri reads a bundle named Skills.skillsbundle", fix: "rename it to Skills.skillsbundle", path: bundlePath))
            }
            let skillsFolder = bundle.appendingPathComponent("Skills")
            for entry in try children(of: bundle) where entry != "Skills" {
                findings.append(.init(severity: .error, code: "stray-file", thing: "\(bundle.lastPathComponent)/\(entry)", problem: "a skills bundle holds only Skills/<name>/SKILL.md", fix: "move \(entry) out of the bundle", path: "\(bundlePath)/\(entry)"))
            }
            var skillsIsDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: skillsFolder.path, isDirectory: &skillsIsDirectory), skillsIsDirectory.boolValue else {
                findings.append(.init(severity: .error, code: "skills-folder-missing", thing: bundle.lastPathComponent, problem: "has no Skills folder", fix: "add Skills/<skill-name>/SKILL.md inside the bundle", path: bundlePath))
                continue
            }
            for name in try children(of: skillsFolder) {
                let folder = skillsFolder.appendingPathComponent(name)
                let shown = "Skills/\(name)"
                var folderIsDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: folder.path, isDirectory: &folderIsDirectory)
                guard folderIsDirectory.boolValue else {
                    findings.append(.init(severity: .error, code: "stray-file", thing: shown, problem: "the Skills folder holds only one folder per skill", fix: "move \(name) out of the bundle", path: folder.path))
                    continue
                }
                skills.append(name)
                if name.wholeMatch(of: /[a-z0-9-]+/) == nil {
                    findings.append(.init(severity: .error, code: "skill-name", thing: shown, problem: "a skill's folder name has only lowercase letters, numbers and hyphens", fix: "rename the folder to \(suggestedName(name))", path: folder.path))
                }
                if let other = seen[name] {
                    findings.append(.init(severity: .error, code: "duplicate-name", thing: shown, problem: "\(other) has a skill with the same name, and the system uses only one of them, which one is undefined", fix: "give one of them another name", path: folder.path))
                } else {
                    seen[name] = bundle.lastPathComponent == "Skills.skillsbundle" ? bundlePath : bundle.lastPathComponent
                }
                let entries = try children(of: folder)
                for entry in entries where entry != "SKILL.md" {
                    findings.append(.init(severity: .error, code: "stray-file", thing: "\(shown)/\(entry)", problem: "a skill folder holds only SKILL.md, and Siri reads no supporting files", fix: "move \(entry) out of the bundle, or fold what Siri needs into SKILL.md", path: folder.appendingPathComponent(entry).path))
                }
                let file = folder.appendingPathComponent("SKILL.md")
                // Compared by name, not fileExists: on a case-insensitive disk skill.md would pass, and fail on device.
                guard entries.contains("SKILL.md") else {
                    findings.append(.init(severity: .error, code: "skill-md-missing", thing: shown, problem: "has no SKILL.md", fix: "add \(shown)/SKILL.md with name and description frontmatter", path: folder.path))
                    continue
                }
                guard let text = try? String(contentsOf: file, encoding: .utf8) else {
                    findings.append(.init(severity: .error, code: "not-utf8", thing: "\(shown)/SKILL.md", problem: "is not UTF-8 text", fix: "save it as UTF-8", path: file.path))
                    continue
                }
                findings += lintSkillFile(text, folderName: name, shown: "\(shown)/SKILL.md", path: file.path)
            }
        }
        if strict { for i in findings.indices { findings[i].exit = OuroAX.ExitCode.findings.code } }
        let errors = findings.filter { $0.severity == .error }.count
        let warnings = findings.count - errors
        let failing = strict ? findings.count : errors
        let exitCode = failing > 0 ? try exits.code("findings") : 0
        let skillWord = skills.count == 1 ? "skill" : "skills"
        let bundleWord = bundles.count == 1 ? "bundle" : "bundles"
        let counted = findings.isEmpty ? "no findings" : [errors > 0 ? "\(errors) error\(errors == 1 ? "" : "s")" : nil, warnings > 0 ? "\(warnings) warning\(warnings == 1 ? "" : "s")" : nil].compactMap { $0 }.joined(separator: ", ")
        return Report(
            ok: exitCode == 0,
            summary: "\(skills.count) \(skillWord) in \(bundles.count) \(bundleWord), \(counted).",
            bundles: bundles.map(\.path),
            skills: skills,
            findings: findings,
            exitCode: exitCode
        )
    }

    static func lintSkillFile(_ text: String, folderName: String, shown: String, path: String) -> [Finding] {
        var findings: [Finding] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---", let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return [.init(severity: .error, code: "frontmatter-missing", thing: shown, problem: "does not start with frontmatter between --- lines", fix: "start the file with ---, name: \(folderName), description: <what it handles>, ---", path: path, line: 1)]
        }
        var fields: [String: (value: String, line: Int)] = [:]
        var last: String?
        for index in 1..<close {
            let line = lines[index]
            if let match = line.firstMatch(of: /^([A-Za-z0-9_-]+)\s*:\s*(.*)$/) {
                let key = String(match.1)
                last = key
                if let earlier = fields[key] {
                    findings.append(.init(severity: .error, code: "frontmatter-duplicate", thing: shown, problem: "the frontmatter sets \(key) twice (lines \(earlier.line) and \(index + 1)), and only one is read", fix: "keep one \(key) line", path: path, line: index + 1))
                }
                fields[key] = (unquote(String(match.2)), index + 1)
                if !allowedFields.contains(key) {
                    findings.append(.init(severity: .error, code: "frontmatter-field", thing: shown, problem: "frontmatter field \(key) is not one Siri reads; app skills take only name and description", fix: "remove \(key) from the frontmatter", path: path, line: index + 1))
                }
            } else if let key = last, line.first?.isWhitespace == true, let field = fields[key] {
                let piece = line.trimmingCharacters(in: .whitespaces)
                fields[key] = ((field.value.isEmpty || field.value == ">" || field.value == "|") ? piece : field.value + " " + piece, field.line)
            }
        }
        for key in ["name", "description"] where (fields[key]?.value ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            findings.append(.init(severity: .error, code: "\(key)-missing", thing: shown, problem: "the frontmatter has no \(key)", fix: key == "name" ? "add name: \(folderName)" : "add description: <the requests this skill handles>", path: path, line: fields[key]?.line ?? 1))
        }
        if let name = fields["name"]?.value, !name.isEmpty, name != folderName {
            findings.append(.init(severity: .warning, code: "name-mismatch", thing: shown, problem: "the frontmatter name \(name) differs from its folder \(folderName)", fix: "use one name for both", path: path, line: fields["name"]?.line))
        }
        let body = lines[(close + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if body.count > maximumBodyCharacters {
            findings.append(.init(severity: .error, code: "body-too-long", thing: shown, problem: "the body is \(body.count) characters; Siri reads at most \(maximumBodyCharacters)", fix: "cut it to \(maximumBodyCharacters) characters, leaving out what the intents' titles and descriptions already say", path: path, line: close + 2))
        }
        if body.isEmpty {
            findings.append(.init(severity: .warning, code: "body-empty", thing: shown, problem: "has no instructions after the frontmatter", fix: "say in plain words which tools to use, in what order, and what to ask the person", path: path, line: close + 2))
        }
        for (offset, line) in lines.enumerated() where offset > close {
            for match in line.matches(of: /\b[A-Z][A-Za-z0-9]*Intent\b/) {
                findings.append(.init(severity: .warning, code: "intent-type-name", thing: shown, problem: "names the intent type \(match.output); Siri knows tools by their titles", fix: "refer to it informally, as \"the \(informal(String(match.output))) tool\"", path: path, line: offset + 1))
            }
        }
        return findings
    }

    /// A folder's entries, leaving out hidden files (Finder's `.DS_Store`, editors' swap files), which Xcode does not
    /// copy into the bundle.
    static func children(of folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { !$0.hasPrefix(".") }.sorted()
    }

    static func unquote(_ value: String) -> String {
        let v = value.trimmingCharacters(in: .whitespaces)
        if v.count >= 2, let first = v.first, let last = v.last, first == last, first == "\"" || first == "'" { return String(v.dropFirst().dropLast()) }
        return v
    }

    static func suggestedName(_ name: String) -> String {
        var spaced = ""
        for (i, c) in name.enumerated() {
            if c.isUppercase, i > 0, let prev = spaced.last, prev.isLowercase || prev.isNumber { spaced.append("-") }
            spaced.append(c)
        }
        let lowered = spaced.lowercased().replacing(/[^a-z0-9]+/, with: "-")
        return lowered.trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty ? "skill" : lowered.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// "StartCookModeIntent" becomes "start cook mode".
    static func informal(_ typeName: String) -> String {
        let base = typeName.hasSuffix("Intent") ? String(typeName.dropLast(6)) : typeName
        return suggestedName(base).replacingOccurrences(of: "-", with: " ")
    }
}
