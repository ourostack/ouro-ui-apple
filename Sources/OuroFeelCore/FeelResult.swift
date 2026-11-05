public import Foundation

/// One thing a check saw. `inferred` marks a reading that goes beyond what was measured (for example, "the simulator
/// may be dropping taps"), so a report never states an inference as a measurement.
public struct FeelFinding: Codable, Equatable, Sendable {
    public var what: String
    public var inferred: Bool

    public init(what: String, inferred: Bool = false) {
        self.what = what
        self.inferred = inferred
    }
}

/// Where and how a check ran: simulator or device, which clock timed it, and whether the app started cold.
public struct FeelEnvironment: Codable, Equatable, Sendable {
    public enum Target: String, Codable, Sendable { case simulator, device, mac }

    /// How the run started. Only `scripts/ouro-feel-cold.sh` sets `cold`; a run it did not start is `unlabelled`, which
    /// a report treats as warm, since a simulator someone used before can hide first-launch problems.
    public enum Start: String, Codable, Sendable {
        case cold, warm, unlabelled

        public init(environment: [String: String]) {
            self = environment["OURO_FEEL_START"].flatMap(Start.init(rawValue:)) ?? .unlabelled
        }

        var words: String {
            switch self {
            case .cold: "cold start (fresh simulator)"
            case .warm: "warm start"
            case .unlabelled: "start not labelled, so treat as warm (not run by ouro-feel-cold.sh)"
            }
        }
    }

    public var target: Target
    public var model: String
    public var os: String
    public var start: Start
    public var clock: String

    public init(target: Target, model: String, os: String, start: Start, clock: String) {
        self.target = target
        self.model = model
        self.os = os
        self.start = start
        self.clock = clock
    }

    /// This process's environment. In a UI test this is the test runner, which runs where the app runs.
    public static func current(clock: String) -> FeelEnvironment {
        let env = ProcessInfo.processInfo.environment
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        #if os(iOS)
        let platform = "iOS"
        #elseif os(macOS)
        let platform = "macOS"
        #elseif os(visionOS)
        let platform = "visionOS"
        #else
        let platform = "OS"
        #endif
        #if targetEnvironment(simulator)
        let target = Target.simulator
        let model = env["SIMULATOR_DEVICE_NAME"] ?? env["SIMULATOR_MODEL_IDENTIFIER"] ?? "simulator"
        #elseif os(macOS)
        let target = Target.mac
        let model = "Mac"
        #else
        let target = Target.device
        var info = utsname()
        uname(&info)
        let model = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        #endif
        return FeelEnvironment(target: target, model: model, os: "\(platform) \(version)", start: Start(environment: env), clock: clock)
    }

    var words: String { "\(target.rawValue) (\(model), \(os)), \(start.words); timed by \(clock)" }
}

/// What one check found. `passed` is the verdict, `measures` the numbers behind it, and `text` the report an agent
/// pastes: it always says where it ran, which clock timed it, and which findings are inference.
public struct FeelResult: Codable, Equatable, Sendable {
    public var check: String
    public var passed: Bool
    public var summary: String
    public var measures: [String: Double]
    public var findings: [FeelFinding]
    public var environment: FeelEnvironment?

    public init(check: String, passed: Bool, summary: String, measures: [String: Double] = [:], findings: [FeelFinding] = [],
                environment: FeelEnvironment? = nil) {
        self.check = check
        self.passed = passed
        self.summary = summary
        // JSON has no infinity or NaN; a measure that is not a number stays out of the report.
        self.measures = measures.filter { $0.value.isFinite }
        self.findings = findings
        self.environment = environment
    }

    public var text: String {
        var lines = ["\(passed ? "PASS" : "FAIL") \(check): \(summary)"]
        lines += findings.map { "  - \($0.what)\($0.inferred ? " (inference)" : "")" }
        if !measures.isEmpty {
            lines.append("  measured: " + measures.keys.sorted().map { "\($0)=\(Self.number(measures[$0]!))" }.joined(separator: ", "))
        }
        if let environment { lines.append("  on \(environment.words)") }
        return lines.joined(separator: "\n")
    }

    public var json: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e9 ? String(Int(value)) : String(format: "%.3f", value)
    }
}

/// Rounds a measure to the millisecond (or thousandth), so reports and assertions are stable.
func round3(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
