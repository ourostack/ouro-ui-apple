/// Where on a control a single tap lands.
public enum FeelTapSpot: String, Codable, CaseIterable, Sendable {
    case centre
    case leadingEdge = "leading edge"
    case trailingEdge = "trailing edge"
    case topEdge = "top edge"
    case bottomEdge = "bottom edge"
    /// The row's title, for a row that acts as one control.
    case title
    /// The space between a row's title and its control.
    case gap
    /// A press of zero length: down and up at once.
    case zeroPress = "zero-length press"
}

/// One tap, never retried. `expected` says whether the tap should change the control: a tap on a gap usually should
/// not, and one that does is as wrong as a miss.
public struct FeelTapTrial: Codable, Equatable, Sendable {
    public var spot: FeelTapSpot
    public var landed: Bool
    public var expected: Bool

    public init(spot: FeelTapSpot, landed: Bool, expected: Bool = true) {
        self.spot = spot
        self.landed = landed
        self.expected = expected
    }
}

/// Rapid taps, as a person taps while a control is still animating, on a control with two states (a switch, a
/// checkbox): double taps, each from a settled control. A pair that ends where it started had both taps land, or
/// neither; one that ends changed lost a tap. It is read from where the control ends, so it is an inference about each
/// tap, and it is scored only when the paced single taps at the centre all landed (so a tap there does land). XCUITest's single taps
/// wait for the app to go idle (about 0.6 s apart), so only its double tap sends taps faster than an animation.
///
/// "Neither landed" also ends where it started, so pairs that all did are trusted only after a triple tap (an odd
/// burst) ended changed, which shows quick taps reach the control.
public struct FeelRapidTaps: Codable, Equatable, Sendable {
    public var pairs: Int
    /// Pairs that ended where they started.
    public var endedWhereStarted: Int
    /// Whether a triple tap ended changed; nil when none was sent.
    public var tripleChanged: Bool?

    public init(pairs: Int, endedWhereStarted: Int, tripleChanged: Bool? = nil) {
        self.pairs = pairs
        self.endedWhereStarted = endedWhereStarted
        self.tripleChanged = tripleChanged
    }

    public var rate: Double { pairs == 0 ? 1 : Double(endedWhereStarted) / Double(pairs) }
}

/// The single-tap landing rate.
public enum FeelTaps {
    /// Passes when at least `minimumRate` of the taps that should land do (by default every one), and no tap that
    /// should not change the control does. `baseline` is an OS control's rate on the same simulator; when it also
    /// missed, the misses may be the simulator's, which the report marks as inference.
    ///
    /// `rapid` is double taps on the same control (``FeelRapidTaps``); `rapidBaseline` is the OS switch's rate for the
    /// same double taps on the same simulator, reported as context: every pair must end where it started either way.
    public static func evaluate(_ trials: [FeelTapTrial], minimumRate: Double = 1, baseline: Double? = nil,
                                rapid: FeelRapidTaps? = nil, rapidBaseline: Double? = nil) -> FeelResult {
        let should = trials.filter(\.expected)
        let landed = should.filter(\.landed).count
        let rate = should.isEmpty ? 1 : Double(landed) / Double(should.count)
        var findings: [FeelFinding] = []
        for spot in FeelTapSpot.allCases {
            let here = should.filter { $0.spot == spot }
            let hits = here.filter(\.landed).count
            if hits < here.count { findings.append(FeelFinding(what: "\(spot.rawValue): \(hits) of \(here.count) single taps landed")) }
            let stray = trials.filter { !$0.expected && $0.spot == spot && $0.landed }.count
            if stray > 0 { findings.append(FeelFinding(what: "\(spot.rawValue): \(stray) taps changed the control, which they should not")) }
        }
        let passed = rate >= minimumRate && !trials.contains { !$0.expected && $0.landed }
        var measures = ["rate": round3(rate), "trials": Double(should.count), "landed": Double(landed)]
        if let baseline {
            measures["baseline"] = round3(baseline)
            if baseline < 1 && rate < 1 {
                findings.append(FeelFinding(what: "the OS control landed \(Int((baseline * 100).rounded()))% on this simulator too, "
                    + "so some misses may be the simulator's; confirm on a device", inferred: true))
            }
        }
        var summary = "\(landed) of \(should.count) single taps landed, no retries"
        var rapidPassed = true
        if let rapid {
            summary += "; rapid: \(rapid.endedWhereStarted) of \(rapid.pairs) double taps ended where they started"
            measures["rapid rate"] = round3(rapid.rate)
            measures["rapid pairs"] = Double(rapid.pairs)
            if let rapidBaseline { measures["rapid baseline"] = round3(rapidBaseline) }
            // The double taps go to the centre: only a centre where single taps land makes "ended where it started" mean
            // both landed rather than neither.
            let centre = should.filter { $0.spot == .centre }
            if centre.isEmpty || centre.contains(where: { !$0.landed }) {
                rapidPassed = false
                findings.append(.couldNotCheck("the double taps were not scored: single taps at the centre missed or were not tried, so a pair that ended where it started may have had no tap land"))
            } else {
                // The bar is absolute: every pair ends where it started. The OS switch's rate is context only and
                // never turns a fail into a pass (UIKit's own switch drops the second tap on the iOS 27.2 simulator).
                let os = rapidBaseline.map { Int(($0 * Double(rapid.pairs)).rounded()) }
                let context = os.map { $0 < rapid.pairs ? "; the OS control also drops these (kept both in \($0) of \(rapid.pairs) on this simulator)"
                                                        : "; the OS switch kept both in \($0) of \(rapid.pairs) on this simulator" } ?? ""
                if rapid.endedWhereStarted < rapid.pairs {
                    rapidPassed = false
                    findings.append(FeelFinding(what: "rapid taps: \(rapid.endedWhereStarted) of \(rapid.pairs) double taps ended where they started, "
                        + "so the rest lost a tap" + context, inferred: true))
                } else if rapid.tripleChanged != true {
                    rapidPassed = false
                    findings.append(.couldNotCheck(rapid.tripleChanged == false
                        ? "a triple tap left the control unchanged, so quick taps may not reach it and a pair that ended where it started may have had no tap land"
                        : "no triple tap was sent, so a pair that ended where it started may have had no tap land"))
                } else if !context.isEmpty {
                    findings.append(.note(String(context.dropFirst(2))))
                }
            }
        }
        return FeelResult(check: FeelGenre.tapLanding.rawValue, passed: passed && rapidPassed, summary: summary,
                          measures: measures, findings: findings)
    }
}
