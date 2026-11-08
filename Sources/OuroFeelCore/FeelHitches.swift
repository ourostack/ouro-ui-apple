/// Hitches from frame timestamps: a frame that arrives more than a quarter of a refresh late is a hitch, and its
/// lateness is hitch time. The ratio is hitch milliseconds per second; Apple counts under 5 as good and over 10 as
/// critical (WWDC20, "Eliminate animation hitches with XCTest").
///
/// The timestamps come from a display link inside the app (the HX gallery's `FrameProbe`, which this follows), because
/// the simulator's `XCTHitchMetric` and `XCTOSSignpostMetric` report no hitch figures. On the simulator the result is a
/// proxy: frame timing there depends on the Mac running it.
public struct FeelHitches: Codable, Equatable, Sendable {
    public var frames: Int
    public var count: Int
    public var hitchMs: Double
    public var seconds: Double
    /// Hitch milliseconds per second.
    public var ratio: Double
    /// The worst lateness, in refresh intervals.
    public var worstFrames: Double

    public static func analyze(timestamps: [Double], refresh: Double) -> FeelHitches {
        var count = 0, hitch = 0.0, worst = 0.0
        for (a, b) in zip(timestamps, timestamps.dropFirst()) {
            let late = (b - a) - refresh
            if late > refresh * 0.25 {
                count += 1
                hitch += late
                worst = max(worst, late / refresh)
            }
        }
        let seconds = max(0.001, (timestamps.last ?? 0) - (timestamps.first ?? 0))
        return FeelHitches(frames: timestamps.count, count: count, hitchMs: round3(hitch * 1000), seconds: round3(seconds),
                           ratio: round3(hitch * 1000 / seconds), worstFrames: round3(worst))
    }

    /// Passes at or under `limit` ms/s and `worstFrames` refreshes late.
    public func result(limit: Double = 5, worstFramesLimit: Double = 2) -> FeelResult {
        var findings: [FeelFinding] = []
        if frames < 2 { findings.append(.couldNotCheck("fewer than two frame timestamps, so there was no hitch reading")) }
        let ok = findings.isEmpty && ratio <= limit && worstFrames <= worstFramesLimit
        if ratio > limit { findings.append(FeelFinding(what: "hitch ratio \(FeelResult.number(ratio)) ms/s is over \(FeelResult.number(limit))")) }
        if worstFrames > worstFramesLimit {
            findings.append(FeelFinding(what: "one frame came \(FeelResult.number(worstFrames)) refreshes late (limit \(FeelResult.number(worstFramesLimit)))"))
        }
        let summary = frames < 2 ? "could not check: no hitch reading" : "\(count) hitches in \(frames) frames over \(FeelResult.number(seconds)) s"
        return FeelResult(check: FeelGenre.hitches.rawValue, passed: ok, summary: summary,
                          measures: frames < 2 ? ["frames": Double(frames)]
                            : ["ratio": ratio, "hitches": Double(count), "worstFrames": worstFrames, "frames": Double(frames)],
                          findings: findings)
    }
}

extension FeelFilm {
    /// Hitches in a film the app filmed on its own display, one sample per frame (``FeelRecording``): a gap between
    /// samples is the app's main thread stalled, so the motion checks can be right about how something moved while the
    /// app froze for half a second around it (ouro-ui-apple#98). The longest stall is named with its length and where it
    /// fell. A film timed any other way (XCUITest's snapshots) is not one sample per frame and could not be checked.
    public func hitches(refresh: Double, limit: Double = 5, worstFramesLimit: Double = 2) -> FeelResult {
        guard timedBy == FeelRecording.timedBy else {
            return timed(FeelResult(check: FeelGenre.hitches.rawValue, passed: false, summary: "could not check: no hitch reading",
                                    findings: [.couldNotCheck("the film was not sampled every frame on the app's display, so its gaps are not the app's frames")]))
        }
        let stamps = frames.map(\.t)
        var result = FeelHitches.analyze(timestamps: stamps, refresh: refresh).result(limit: limit, worstFramesLimit: worstFramesLimit)
        if let (a, b) = zip(stamps, stamps.dropFirst()).max(by: { $0.1 - $0.0 < $1.1 - $1.0 }), (b - a) - refresh > refresh * worstFramesLimit {
            let refreshes = Int(((b - a) / refresh).rounded())
            result.findings.insert(FeelFinding(what: "the app stalled \(FeelResult.number(round3(b - a))) s (\(refreshes) refreshes) at "
                + "\(FeelResult.number(round3(a))) s"), at: 0)
        }
        if let stall = stall() {
            result.findings.insert(stall, at: 0)
            result.passed = false
        }
        return timed(result)
    }
}
