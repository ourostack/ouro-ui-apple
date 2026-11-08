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
    /// app froze for half a second around it (ouro-ui-apple#98). The longest stall is named with its length, where it
    /// fell and how late it was, in one finding.
    ///
    /// `refresh` defaults to the film's own pace (its median gap), since the film does not record the display's rate; a
    /// `refresh` more than 25% off that pace (60 Hz filmed, 120 Hz assumed) could not be checked, rather than every frame
    /// counting as late. A film made any other way (XCUITest's snapshots, a film on the app's clock) is not one sample per
    /// frame and could not be checked either.
    public func hitches(refresh: Double? = nil, limit: Double = 5, worstFramesLimit: Double = 2) -> FeelResult {
        func unchecked(_ why: String) -> FeelResult {
            timed(FeelResult(check: FeelGenre.hitches.rawValue, passed: false, summary: "could not check: no hitch reading",
                             findings: [.couldNotCheck(why)]))
        }
        guard timedBy == FeelRecording.timedBy else {
            return unchecked("the film was not made by the in-app recorder, one sample per frame, so its gaps are not the app's frames")
        }
        let pace = typicalGap
        let refresh = refresh ?? (pace.isFinite ? pace : 1.0 / 60)
        if pace.isFinite, abs(pace - refresh) > refresh * 0.25 {
            return unchecked("the film's frames came every \(FeelResult.number(round3(pace * 1000))) ms, not every "
                + "\(FeelResult.number(round3(refresh * 1000))) ms as given, so lateness could not be measured")
        }
        let stamps = frames.map(\.t)
        var result = FeelHitches.analyze(timestamps: stamps, refresh: refresh).result(limit: limit, worstFramesLimit: worstFramesLimit)
        if (result.measures["worstFrames"] ?? 0) > worstFramesLimit,
           let (a, b) = zip(stamps, stamps.dropFirst()).max(by: { $0.1 - $0.0 < $1.1 - $1.0 }) {
            // One finding for the one stall: its length, where it fell, and its lateness against the limit.
            result.findings.removeAll { $0.what.hasPrefix("one frame came") }
            result.findings.insert(FeelFinding(what: "the app stalled \(FeelResult.number(round3(b - a))) s at \(FeelResult.number(round3(a))) s, "
                + "\(FeelResult.number(result.measures["worstFrames"] ?? 0)) refreshes late (limit \(FeelResult.number(worstFramesLimit)))"), at: 0)
        }
        if let stall = stall() {
            // What was filmed still counts; the cut-off film says so after it.
            result.findings.append(stall)
            result.passed = false
        }
        return timed(result)
    }
}
