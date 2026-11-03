import Foundation
public import OuroAXSkillsLint

/// `ouro-ax-xray`: the command. Kept here, not in the executable, so tests run it as a function.
public enum XrayCLI {
    public struct Run: Sendable {
        public var code: Int32
        public var stdout: String
        public var stderr: String
    }

    public static let help = """
    ouro-ax-xray \(AXXray.version): checks an app's App Intents against Ouro AX for Apple's claims, from outside the app.

      ouro-ax-xray --app <path.app> [options]          the report
      ouro-ax-xray plan --app <path.app> [--disposable] the behaviour plan, base64, for TEST_RUNNER_OURO_AX_PLAN
      ouro-ax-xray scenarios --app <path.app> --set <scenarios.json> [--swift <out.swift>]
                                                       check a Siri scenario set against the app; write its test file

    Report options:
      --commit <sha>        the app's commit, pinned in the report
      --name <name>         the app's name in the report (default: from Info.plist)
      --probe <file>        a behaviour run's result: its JSON, or a test log holding OURO-AX-PROBE-BEGIN/END
      --siri <file>         SiriEvaluations runs, the JSON lines the generated tests append
      --siri-on <text>      where those runs happened (default: "SiriEvaluations")
      --threshold <0..1>    the pass rate a Siri scenario needs (default 0.8)
      --claims <file>       a claim set other than the one vendored from ouro-ui-core
      --format text|json|md|html   what to print (default text)
      --out <dir>           also write report.json, report.md and report.html there
      --conformance         exit 1 unless the app conforms

    The metadata stage reads Metadata.appintents/extract.actionsdata in the built app. The behaviour stage runs in a
    test bundle (Templates/XrayProbe) because AppIntentsTesting runs only there; pass its log with --probe.
    """

    struct Usage: Error { var message: String }

    static func value(_ args: [String], _ flag: String) throws -> String? {
        guard let i = args.firstIndex(of: flag) else { return nil }
        guard i + 1 < args.count, !args[i + 1].hasPrefix("--") else { throw Usage(message: "\(flag) needs a value") }
        return args[i + 1]
    }

    /// The app's Info.plist values: bundle identifier, name and platform.
    static func appInfo(_ app: URL) throws -> (id: String, name: String, platform: String) {
        let mac = app.appendingPathComponent("Contents/Info.plist")
        let url = FileManager.default.fileExists(atPath: mac.path) ? mac : app.appendingPathComponent("Info.plist")
        guard let data = FileManager.default.contents(atPath: url.path),
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = plist["CFBundleIdentifier"] as? String else {
            throw Usage(message: "\(app.path) has no Info.plist with a bundle identifier; pass a built .app")
        }
        let name = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? app.deletingPathExtension().lastPathComponent
        let platforms = plist["CFBundleSupportedPlatforms"] as? [String] ?? []
        let platform = url == mac ? "macOS" : platforms.first.map { $0 == "iPhoneSimulator" ? "iOS Simulator" : $0 == "iPhoneOS" ? "iOS" : $0 } ?? "iOS"
        return (id, name, platform)
    }

    /// Every `.skillsbundle` inside the app.
    static func skillsBundles(in app: URL) -> [URL] {
        guard let walk = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else { return [] }
        var out: [URL] = []
        for case let url as URL in walk where url.pathExtension == "skillsbundle" {
            out.append(url)
            walk.skipDescendants()
        }
        return out.sorted { $0.path < $1.path }
    }

    public static func run(_ arguments: [String]) -> Run {
        var out = "", err = ""
        do {
            if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") { return Run(code: 0, stdout: help + "\n", stderr: "") }
            if arguments.contains("--version") { return Run(code: 0, stdout: "ouro-ax-xray \(AXXray.version)\n", stderr: "") }
            let command = arguments[0].hasPrefix("--") ? "report" : arguments[0]
            let args = command == "report" ? arguments : Array(arguments.dropFirst())
            guard ["report", "plan", "scenarios"].contains(command) else { throw Usage(message: "no command \(command); see --help") }
            // A misspelt flag must not pass silently in CI.
            let valued: Set = ["--app", "--commit", "--name", "--probe", "--siri", "--siri-on", "--threshold", "--claims", "--format", "--out", "--set", "--swift"]
            let switches: Set = ["--conformance", "--disposable"]
            var i = 0
            while i < args.count {
                let a = args[i]
                if valued.contains(a) { i += 2; continue }
                if switches.contains(a) { i += 1; continue }
                throw Usage(message: "unknown argument \(a); see --help")
            }
            guard let appPath = try value(args, "--app") else { throw Usage(message: "--app <path.app> is required") }
            let app = URL(fileURLWithPath: appPath)
            let info = try appInfo(app)
            let inventory = try AXXray.Inventory.metadataURL(inApp: app).map { try AXXray.Inventory(actionsData: Data(contentsOf: $0)) }

            switch command {
            case "plan":
                guard let inventory else { throw Usage(message: "\(info.name) has no App Intents metadata, so there is nothing to probe") }
                let plan = AXXray.ProbePlan(bundleIdentifier: info.id, inventory: inventory, refusals: args.contains("--disposable"))
                out = try JSONEncoder().encode(plan).base64EncodedString() + "\n"
                return Run(code: 0, stdout: out, stderr: "")
            case "scenarios":
                guard let inventory else { throw Usage(message: "\(info.name) has no App Intents metadata") }
                guard let setPath = try value(args, "--set") else { throw Usage(message: "--set <scenarios.json> is required") }
                let set = try JSONDecoder().decode(AXXray.SiriScenarioSet.self, from: Data(contentsOf: URL(fileURLWithPath: setPath)))
                let problems = set.problems(against: inventory)
                if let swift = try value(args, "--swift") { try set.swiftSource().write(toFile: swift, atomically: true, encoding: .utf8) }
                out = problems.isEmpty ? "\(set.scenarios.count) scenarios, every intent, parameter and entity in \(info.name)'s metadata\n" : problems.map { "problem: \($0)" }.joined(separator: "\n") + "\n"
                return Run(code: problems.isEmpty ? 0 : 3, stdout: out, stderr: "")
            default:
                break
            }

            let set = try value(args, "--claims").map { try AXXray.ClaimSet(data: Data(contentsOf: URL(fileURLWithPath: $0))) } ?? AXXray.ClaimSet.bundled()
            let bundles = skillsBundles(in: app)
            let skills = bundles.isEmpty ? nil : try SkillsLint.lint(bundles)
            let probe = try value(args, "--probe").map { path -> AXXray.ProbeResult in
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                if let fromLog = try AXXray.ProbeResult.fromLog(String(decoding: data, as: UTF8.self)) { return fromLog }
                return try JSONDecoder().decode(AXXray.ProbeResult.self, from: data)
            }
            if let probe, probe.bundleIdentifier != info.id { throw Usage(message: "the probe ran against \(probe.bundleIdentifier), not \(info.id)") }
            let threshold = try value(args, "--threshold").map { guard let t = Double($0), (0...1).contains(t) else { throw Usage(message: "--threshold is a number from 0 to 1") }; return t } ?? 0.8
            let siri = try value(args, "--siri").map {
                try AXXray.siriResults(jsonLines: String(contentsOfFile: $0, encoding: .utf8), ranOn: try value(args, "--siri-on") ?? "SiriEvaluations", threshold: threshold)
            }
            let report = AXXray.report(set, .init(inventory: inventory, skills: skills, probe: probe, siri: siri),
                                       name: try value(args, "--name") ?? info.name, bundleIdentifier: info.id, platform: info.platform, commit: try value(args, "--commit"))
            if let dir = try value(args, "--out") {
                let d = URL(fileURLWithPath: dir)
                try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
                try report.json().write(to: d.appendingPathComponent("report.json"))
                try report.markdown().write(to: d.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
                try report.html().write(to: d.appendingPathComponent("report.html"), atomically: true, encoding: .utf8)
                err += "wrote report.json, report.md and report.html to \(d.path)\n"
            }
            switch try value(args, "--format") ?? "text" {
            case "text": out = report.text()
            case "json": out = String(decoding: try report.json(), as: UTF8.self)
            case "md": out = report.markdown()
            case "html": out = report.html()
            case let f: throw Usage(message: "--format \(f): use text, json, md or html")
            }
            return Run(code: args.contains("--conformance") && !report.conformant ? 1 : 0, stdout: out, stderr: err)
        } catch let u as Usage {
            return Run(code: 2, stdout: out, stderr: "ouro-ax-xray: \(u.message)\n")
        } catch {
            return Run(code: 2, stdout: out, stderr: "ouro-ax-xray: \(error.localizedDescription)\n")
        }
    }
}
