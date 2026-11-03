import Foundation
import OuroAX

/// `ouro-ax-skills`: the command line, kept in the library so tests run it without a process.
public enum SkillsCLI {
    public static let tool = "ouro-ax-skills"

    public struct Run: Sendable {
        public var code: Int32
        public var stdout: String
        public var stderr: String
    }

    public static let help = """
    ouro-ax-skills: lint app-skills bundles (Skills.skillsbundle) for Siri AI.

    Usage:
      ouro-ax-skills lint <bundle>... [--json | --format text|json|xcode] [--strict] [--stamp <file>]

    Rules (errors): one Skills folder; each skill is Skills/<name>/SKILL.md and nothing else; names use only lowercase
    letters, numbers and hyphens and are unique across the bundles given; frontmatter holds only name and description,
    both present; the body is at most 10,000 characters.
    Rules (warnings, findings under --strict): the frontmatter name matches its folder; the body is not empty; the body
    names tools informally ("the search tool"), never by intent type name.

    \(SkillsLint.exits.line())
    """

    enum Format: String { case text, json, xcode }

    public static func run(_ arguments: [String]) -> Run {
        var args = arguments[...]
        guard let command = args.popFirst() else {
            return usage(.init(code: "missing-arg", exit: 2, thing: "lint", problem: "needs a bundle path", fix: "\(tool) lint <path-to-Skills.skillsbundle>"), format: .text)
        }
        if command == "--help" || command == "-h" || command == "help" {
            return Run(code: 0, stdout: help + "\n", stderr: "")
        }
        var format = Format.text
        var strict = false
        var paths: [String] = []
        var stamp: String?
        var rest = Array(args)
        if rest.contains("--json") { format = .json }
        guard command == "lint" else {
            let fix = OuroAX.Problem.didYouMean(command, in: ["lint", "help"]).map { OuroAX.commandLine([tool, $0] + rest) } ?? "\(tool) lint <path-to-Skills.skillsbundle>"
            return usage(.init(code: "unknown-command", exit: 2, thing: command, problem: "is not a command", fix: fix), format: format)
        }
        while !rest.isEmpty {
            let arg = rest.removeFirst()
            switch arg {
            case "--json": format = .json
            case "--strict": strict = true
            case "--format":
                guard let value = rest.first, let chosen = Format(rawValue: value) else {
                    return usage(.init(code: "bad-value", exit: 2, thing: "lint --format", problem: "takes text, json or xcode", fix: "\(tool) lint <bundle> --format xcode"), format: format)
                }
                rest.removeFirst()
                format = chosen
            case "--stamp":
                guard let value = rest.first else {
                    return usage(.init(code: "missing-arg", exit: 2, thing: "lint --stamp", problem: "needs a file path", fix: "\(tool) lint <bundle> --stamp <file>"), format: format)
                }
                rest.removeFirst()
                stamp = value
            case "--help", "-h": return Run(code: 0, stdout: help + "\n", stderr: "")
            default:
                if arg.hasPrefix("-") {
                    let near = OuroAX.Problem.didYouMean(arg, in: ["--json", "--strict", "--format", "--stamp"])
                    return usage(.init(code: "unknown-flag", exit: 2, thing: "lint \(arg)", problem: "is not a flag", fix: near.map { "use \($0)" } ?? "\(tool) --help"), format: format)
                }
                paths.append(arg)
            }
        }
        guard !paths.isEmpty else {
            return usage(.init(code: "missing-arg", exit: 2, thing: "lint", problem: "needs a bundle path", fix: "\(tool) lint <path-to-Skills.skillsbundle>"), format: format)
        }
        let report: SkillsLint.Report
        do {
            report = try SkillsLint.lint(paths.map { URL(fileURLWithPath: $0) }, strict: strict)
        } catch let error as SkillsLint.UsageError {
            return usage(error.problem, format: format)
        } catch {
            let problem = OuroAX.Problem(code: "crashed", exit: 1, thing: "lint", problem: "could not read the bundle (\(error.localizedDescription))", fix: "check the bundle's files are readable")
            return Run(code: 1, stdout: format == .json ? json(["error": problem]) : "", stderr: problem.line(tool: tool) + "\n")
        }
        // The build-tool plugin's output: written only when the lint passes, so the build reruns it until it does.
        if let stamp, report.exitCode == 0 {
            try? Data(("// ouro-ax-skills: " + report.summary + "\n").utf8).write(to: URL(fileURLWithPath: stamp))
        }
        switch format {
        case .json:
            return Run(code: Int32(report.exitCode), stdout: json(report), stderr: "")
        case .xcode:
            let lines = report.findings.map { "\($0.path):\($0.line.map(String.init) ?? "1"): \($0.severity.rawValue): \($0.message)" }
            return Run(code: Int32(report.exitCode), stdout: lines.map { $0 + "\n" }.joined(), stderr: "")
        case .text:
            let verdict = report.findings.isEmpty ? "ok" : (report.exitCode == 0 ? "warnings" : "findings")
            var lines = ["\(verdict): \(report.summary)"]
            for f in report.findings {
                lines.append("\(f.severity == .error ? "error  " : "warning")  \(f.message)\(f.line.map { "  (line \($0))" } ?? "")")
            }
            return Run(code: Int32(report.exitCode), stdout: lines.joined(separator: "\n") + "\n", stderr: "")
        }
    }

    static func usage(_ problem: OuroAX.Problem, format: Format) -> Run {
        Run(code: Int32(problem.exit), stdout: format == .json ? json(["error": problem]) : "", stderr: problem.line(tool: tool) + "\n")
    }

    static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return ((try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}") + "\n"
    }
}
