public import Foundation

// MARK: Screen flicker (oscillation)

/// One sample of the whole screen: a small grayscale picture (one byte a pixel, row by row), with whatever the film was
/// told to ignore (the status bar, the app's clock) already blanked.
public struct FeelScreenFrame: Codable, Equatable, Sendable {
    public var t: Double
    public var width: Int
    public var height: Int
    public var gray: [UInt8]

    public init(t: Double, width: Int, height: Int, gray: [UInt8]) {
        self.t = t
        self.width = width
        self.height = height
        self.gray = gray
    }
}

/// A film of the whole screen, for apps whose content no element names (a web view, a canvas, a video): flicker judged
/// from pixels. ``FeelFilm/flickers(of:within:changes:distance:hold:maxGap:tolerance:)`` judges named elements; this
/// judges what is on screen, so it catches a page that goes A, B, A where no label ever changes.
public struct FeelScreenFilm: Codable, Equatable, Sendable {
    public var frames: [FeelScreenFrame]
    /// When the film stopped early (the app's clock stopped), in seconds; nil when it ran to the end.
    public var stalledAt: Double?
    /// How the samples were timed, for the report.
    public var timedBy: String?

    public init(frames: [FeelScreenFrame], stalledAt: Double? = nil, timedBy: String? = nil) {
        self.frames = frames
        self.stalledAt = stalledAt
        self.timedBy = timedBy
    }

    /// One state the screen rested in: a run of samples that each differ from the one before by under the film's
    /// `stable` threshold. `label` is shared by states that look the same (under `merge` apart).
    public struct State: Equatable, Sendable {
        public var label: Int
        public var start: Int
        public var end: Int
    }

    /// The mean absolute difference of two pictures, 0 to 255; nil when their sizes differ.
    public static func difference(_ a: FeelScreenFrame, _ b: FeelScreenFrame) -> Double? {
        guard a.width == b.width, a.height == b.height, a.gray.count == b.gray.count, !a.gray.isEmpty else { return nil }
        var sum = 0
        for i in 0..<a.gray.count { sum += abs(Int(a.gray[i]) - Int(b.gray[i])) }
        return Double(sum) / Double(a.gray.count)
    }

    /// The states the screen rested in, in order: runs of at least `run` samples, each under `stable` from the one
    /// before. A state takes the label of the first earlier state whose first picture is under `merge` from its own.
    /// Samples in between (on their way) belong to no state.
    public func states(stable: Double = 0.6, merge: Double = 1.5, run: Int = 2) -> [State] {
        var out: [State] = []
        var reps: [Int] = []  // the first sample of each label
        var i = 0
        while i < frames.count {
            var j = i
            while j + 1 < frames.count, let d = Self.difference(frames[j], frames[j + 1]), d < stable { j += 1 }
            if j - i + 1 >= max(1, run) {
                let label = reps.firstIndex { r in Self.difference(frames[r], frames[i]).map { $0 < merge } ?? false } ?? {
                    reps.append(i)
                    return reps.count - 1
                }()
                if let last = out.last, last.label == label {
                    out[out.count - 1].end = j
                } else {
                    out.append(State(label: label, start: i, end: j))
                }
            }
            i = j + 1
        }
        return out
    }

    /// Flicker of the whole screen within one action, judged in samples, never seconds. It fails when the screen comes
    /// back to a state it left (A, B, A) within `within` samples, and when it rests in more than `states` different
    /// states (a contents jump that shows a veil, then the page, declares 3: where it was, the veil, the page). Overlays
    /// the action itself toggles, and slips the app means to show, are declared by raising `states`; a slip that shows
    /// and goes again is still A, B, A, so blank its region when filming if it is meant to come and go.
    ///
    /// The pictures are compared as small grayscale thumbnails: two samples under `stable` (mean absolute difference, 0
    /// to 255) apart are the same moment of a rest; a rest is at least `run` samples; two rests under `merge` apart are
    /// the same state. It cannot be checked when the film stalled, when its pictures differ in size, or when the screen
    /// was still changing in its last `run` samples (film for longer).
    public func flickers(within: Int = 90, states allowed: Int = 2, stable: Double = 0.6, merge: Double = 1.5,
                         run: Int = 2) -> FeelResult {
        let run = max(2, run)
        var findings: [FeelFinding] = []
        if let at = stalledAt {
            findings.append(.couldNotCheck("the film stopped at \(FeelResult.number(Self.round3(at))) s (the app's clock stopped), so the rest was never seen"))
        }
        let sizes = Set(frames.map { "\($0.width)x\($0.height)" })
        if sizes.count > 1 {
            findings.append(.couldNotCheck("the film's pictures were not all one size (\(sizes.sorted().joined(separator: ", "))), so they cannot be compared"))
        }
        if frames.count < run {
            findings.append(.couldNotCheck("the film had \(frames.count) samples, fewer than the \(run) a rest needs; film for longer"))
        }
        let found = sizes.count > 1 ? [] : states(stable: stable, merge: merge, run: run)
        var flips = 0
        if sizes.count <= 1, frames.count >= run {
            for (n, state) in found.enumerated() where n >= 2 {
                guard let earlier = found[..<(n - 1)].last(where: { $0.label == state.label }) else { continue }
                let gap = state.start - earlier.end
                guard gap <= within else { continue }
                flips += 1
                findings.append(FeelFinding(what: "the screen left a state at \(FeelResult.number(Self.round3(frames[earlier.end].t))) s and came back to it \(gap) samples later, at \(FeelResult.number(Self.round3(frames[state.start].t))) s"))
            }
            let distinct = Set(found.map(\.label)).count
            if distinct > allowed {
                flips += 1
                findings.append(FeelFinding(what: "the screen rested in \(distinct) different states, more than the \(allowed) this action declares"))
            }
            if let last = found.last, last.end < frames.count - 1 {
                findings.append(.couldNotCheck("the screen was still changing in the film's last \(frames.count - 1 - last.end) samples, so whether it settled was not seen; film for longer"))
            } else if found.isEmpty {
                findings.append(.couldNotCheck("the screen never rested for \(run) samples; film for longer"))
            }
        }
        let result = FeelResult.judged(
            check: FeelGenre.flicker.rawValue,
            passing: "the screen never came back to a state it left in \(frames.count) samples",
            failing: { "\($0) screen \($0 == 1 ? "flicker" : "flickers") in \(frames.count) samples" },
            measures: ["flickers": Double(flips), "samples": Double(frames.count), "states": Double(Set(found.map(\.label)).count)],
            findings: findings)
        guard let timedBy, result.environment == nil else { return result }
        var stamped = result
        stamped.environment = FeelEnvironment.current(clock: timedBy)
        return stamped
    }

    static func round3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }
}
