public import OuroAX

/// Test helpers for apps that use OuroAX. Today: the pure parts of a Siri evaluation (wordings and pass rates), and
/// a SiriEvaluations adapter behind `#if canImport(SiriEvaluations)`. The App Intents X-ray arrives in W4.
public enum OuroAXTesting {
    /// Siri varies between runs, so a scenario set runs several times and is judged by its pass rate.
    public static let recommendedRuns = 5

    /// The ways a person might ask for one thing. A good evaluation set has all four.
    public struct Wordings: Sendable, Hashable {
        public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
            /// Names the action and the app: "Add milk to my Spoonjoy list".
            case direct
            /// Says the need, not the action: "We're out of milk".
            case indirect
            /// Leaves out a parameter Siri must ask for: "Add something to my list".
            case incomplete
            /// Something the app can't do, or asks oddly: Siri should decline or ask, not guess.
            case unexpected
        }

        public var direct: [String]
        public var indirect: [String]
        public var incomplete: [String]
        public var unexpected: [String]

        public init(direct: [String], indirect: [String] = [], incomplete: [String] = [], unexpected: [String] = []) {
            self.direct = direct
            self.indirect = indirect
            self.incomplete = incomplete
            self.unexpected = unexpected
        }

        /// Every wording with its kind, direct first.
        public var all: [(kind: Kind, text: String)] {
            direct.map { (.direct, $0) } + indirect.map { (.indirect, $0) } + incomplete.map { (.incomplete, $0) } + unexpected.map { (.unexpected, $0) }
        }

        /// The kinds with no wording yet.
        public var missingKinds: [Kind] {
            Kind.allCases.filter { kind in !all.contains { $0.kind == kind } }
        }
    }

    /// How often a scenario passed over repeated runs.
    public struct PassRate: Sendable, Hashable, CustomStringConvertible {
        public var passes: [Bool]
        public init(passes: [Bool]) { self.passes = passes }

        public var runs: Int { passes.count }
        public var passed: Int { passes.filter { $0 }.count }
        /// From 0 to 1; 0 when nothing ran.
        public var value: Double { runs == 0 ? 0 : Double(passed) / Double(runs) }
        /// True when at least one run happened and the rate reaches `threshold`.
        public func meets(_ threshold: Double) -> Bool { runs > 0 && value >= threshold }

        public var description: String { "\(passed)/\(runs) runs passed (\(Int((value * 100).rounded()))%)" }

        /// A finding (exit 3) when the rate is under `threshold`, else nil.
        public func problem(scenario: String, threshold: Double) -> OuroAX.Problem? {
            guard !meets(threshold) else { return nil }
            return .init(
                code: "pass-rate", exit: OuroAX.ExitCode.findings.code, thing: scenario,
                problem: "\(description), under \(Int((threshold * 100).rounded()))%",
                fix: "read the failing runs' transcripts and tighten the intent's title, description or app skill"
            )
        }
    }
}
