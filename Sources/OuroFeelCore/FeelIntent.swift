/// What happened after a tap that starts slow work, for ``FeelIntent/judge(_:)``.
public struct FeelIntentTrail: Codable, Equatable, Sendable {
    /// What the person asked for, in the report's words ("open \"Moby-Dick\"").
    public var intent: String
    /// The control tapped, by identifier or label.
    public var control: String
    /// Seconds from the first tap until the intent was done, nil if it never was before the screen settled or time ran out.
    public var doneAfterFirst: Double?
    /// Seconds from the first tap until the screen held still without the intent done; nil if it never settled.
    public var settledAfter: Double?
    /// Whether the same control was there to tap again once the screen settled.
    public var controlBack: Bool
    /// Seconds from a second tap until the intent was done; nil if there was no second tap or it did not finish.
    public var doneAfterSecond: Double?
    /// Whether a second tap was sent.
    public var tappedTwice: Bool
    /// How long the check waited for each tap's work.
    public var within: Double

    public init(intent: String, control: String, doneAfterFirst: Double? = nil, settledAfter: Double? = nil,
                controlBack: Bool = false, doneAfterSecond: Double? = nil, tappedTwice: Bool = false, within: Double) {
        self.intent = intent
        self.control = control
        self.doneAfterFirst = doneAfterFirst
        self.settledAfter = settledAfter
        self.controlBack = controlBack
        self.doneAfterSecond = doneAfterSecond
        self.tappedTwice = tappedTwice
        self.within = within
    }
}

/// One action finishes the intent, under your intent is the unit: a tap that starts asynchronous work (a download, a
/// load, a sign-in) completes what the person asked for once the work is done, if they are still there.
///
/// From Gatefold, 2026-11-27: opening a book that was not downloaded downloaded it and stopped there; it took a second
/// tap to open it. The check taps once and waits for the intent, keeping busy screens (progress, spinners, changing
/// words) apart from settled ones. When the screen settles with the intent not done and the same control is back, it
/// taps a second time: if that finishes the intent, the first tap's work was dropped, and that fails.
public enum FeelIntent {
    public static func judge(_ trail: FeelIntentTrail) -> FeelResult {
        var findings: [FeelFinding] = []
        var measures: [String: Double] = ["taps": trail.tappedTwice ? 2 : 1]
        if let done = trail.doneAfterFirst {
            measures["seconds"] = round3(done)
        } else if trail.tappedTwice, let second = trail.doneAfterSecond {
            measures["second tap seconds"] = round3(second)
            findings.append(FeelFinding(what: "\(trail.intent) took a second tap on \"\(trail.control)\": the first tap's work "
                + "ended after \(seconds(trail.settledAfter ?? trail.within)) s without finishing it, and the "
                + "same tap again did, after \(seconds(second)) s"))
        } else if trail.tappedTwice {
            findings.append(.couldNotCheck("\(trail.intent) was not done \(seconds(trail.within)) s after a tap on "
                + "\"\(trail.control)\", nor after a second tap: the work may have failed (check the fixture's state) or need longer (raise within:)"))
        } else if trail.settledAfter != nil && !trail.controlBack {
            findings.append(.couldNotCheck("\(trail.intent) was not done when the screen settled "
                + "\(seconds(trail.settledAfter ?? 0)) s after the tap, and \"\(trail.control)\" was gone, so "
                + "no second tap could show whether the work was dropped"))
        } else {
            findings.append(.couldNotCheck("\(trail.intent) was not done \(seconds(trail.within)) s after a tap on "
                + "\"\(trail.control)\", and the screen was still busy (raise within:)"))
        }
        return FeelResult.judged(check: FeelCheck.oneAction.name,
                                 passing: "one tap on \"\(trail.control)\" finished \(trail.intent) in "
                                    + "\(seconds(trail.doneAfterFirst ?? 0)) s",
                                 failing: { _ in "\(trail.intent) took two taps" },
                                 measures: measures, findings: findings)
    }

    /// Seconds to a tenth, as a person reads them.
    static func seconds(_ value: Double) -> String { String(format: "%.1f", value) }
}
