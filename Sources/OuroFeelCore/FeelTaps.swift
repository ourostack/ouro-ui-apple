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

/// The single-tap landing rate.
public enum FeelTaps {
    /// Passes when at least `minimumRate` of the taps that should land do (by default every one), and no tap that
    /// should not change the control does. `baseline` is an OS control's rate on the same simulator; when it also
    /// missed, the misses may be the simulator's, which the report marks as inference.
    public static func evaluate(_ trials: [FeelTapTrial], minimumRate: Double = 1, baseline: Double? = nil) -> FeelResult {
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
        return FeelResult(check: FeelGenre.tapLanding.rawValue, passed: passed, summary: "\(landed) of \(should.count) single taps landed, no retries",
                          measures: measures, findings: findings)
    }
}
