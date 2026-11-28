public import CoreGraphics

/// One look at the screen while nothing touches it: where each control and piece of chrome is, by key, and whether
/// the status bar shows (nil when it could not be read).
public struct FeelIdleSample: Codable, Equatable, Sendable {
    public var at: Double
    public var elements: [String: CGRect]
    public var statusBar: Bool?

    public init(at: Double, elements: [String: CGRect], statusBar: Bool?) {
        self.at = at
        self.elements = elements
        self.statusBar = statusBar
    }
}

/// Still while idle, part of the flicker genre: with no input, nothing on screen changes. No control or piece of
/// chrome appears, goes or moves, and the status bar neither shows nor hides. From Gatefold's reader on the open
/// iPhone Duo (Ari, 2026-11-15), whose close button and status bar took turns several times a second with no touch, as
/// a layout loop: the status bar changes the safe area, which moves the chrome, which flips the status bar again.
/// Start sampling once the screen has landed; any change after that is a failure.
public enum FeelIdle {
    /// Movement of half a point or less is rounding, not a move.
    public static let tolerance: CGFloat = 0.5

    /// The looks `check` needs to judge a screen.
    public static let leastLooks = 3
    /// How long a watch may run, as a multiple of its window, while it still lacks `leastLooks` looks.
    public static let lookCapFactor = 3.0

    /// Looks at the screen with no input for `seconds`, at most every `every` seconds, and on until it has
    /// `leastLooks` looks: when the looks slow down partway, a window sized from a quick one held only 2 and the
    /// check could not judge a still screen (#284). It adds looks and drops none, so a move is never missed; once the
    /// watch has run `lookCapFactor` times its window it stops, and a watch still short of looks is could-not-check,
    /// never a pass. `now` reads the clock in seconds, `look` takes one look (given its time since the start) and
    /// `pause` waits.
    public static func watch(for seconds: Double, every: Double, now: () -> Double,
                             look: (Double) -> FeelIdleSample, pause: (Double) -> Void) -> [FeelIdleSample] {
        watch(for: seconds, every: every, now: now, first: nil, look: look, pause: pause)
    }

    /// The same watch, starting from a look already taken: `first` is that look and the clock time it was taken, as
    /// the wait for content takes it, so a watch whose content was already there costs no extra look.
    public static func watch(for seconds: Double, every: Double, now: () -> Double,
                             first: (sample: FeelIdleSample, at: Double)?,
                             look: (Double) -> FeelIdleSample, pause: (Double) -> Void) -> [FeelIdleSample] {
        var samples: [FeelIdleSample] = []
        let start = first?.at ?? now()
        if var sample = first?.sample {
            sample.at = 0
            samples.append(sample)
            let rest = every - (now() - start)
            if rest > 0 { pause(rest) }
        }
        while now() - start < seconds || (samples.count < leastLooks && now() - start < seconds * lookCapFactor) {
            let began = now()
            samples.append(look(began - start))
            let rest = every - (now() - began)
            if rest > 0 { pause(rest) }
        }
        return samples
    }

    public static func check(_ samples: [FeelIdleSample], pose: String) -> FeelResult {
        var findings: [FeelFinding] = []
        var appeared: [String: Int] = [:], moved: [String: Int] = [:]
        var statusFlips = 0
        for (before, after) in zip(samples, samples.dropFirst()) {
            for key in Set(before.elements.keys).union(after.elements.keys) {
                switch (before.elements[key], after.elements[key]) {
                case let (a?, b?):
                    if abs(a.minX - b.minX) > tolerance || abs(a.minY - b.minY) > tolerance
                        || abs(a.width - b.width) > tolerance || abs(a.height - b.height) > tolerance {
                        moved[key, default: 0] += 1
                    }
                case (nil, _?), (_?, nil): appeared[key, default: 0] += 1
                default: break
                }
            }
            if let a = before.statusBar, let b = after.statusBar, a != b { statusFlips += 1 }
        }
        let span = (samples.last?.at ?? 0) - (samples.first?.at ?? 0)
        let over = "over \(FeelResult.number((span * 10).rounded() / 10)) s with no input in \(pose)"
        for key in appeared.keys.sorted() {
            findings.append(FeelFinding(what: "\"\(key)\" appeared or went \(appeared[key]!) times \(over)"))
        }
        for key in moved.keys.sorted() {
            findings.append(FeelFinding(what: "\"\(key)\" moved \(moved[key]!) times \(over)"))
        }
        if statusFlips > 0 { findings.append(FeelFinding(what: "the status bar showed or hid \(statusFlips) times \(over)")) }
        let changes = appeared.values.reduce(0, +) + moved.values.reduce(0, +) + statusFlips
        if samples.count < leastLooks {
            findings.append(.couldNotCheck("only \(samples.count) looks at the screen in \(pose); it takes at least 3"))
        } else if samples.allSatisfy({ $0.elements.isEmpty }) {
            findings.append(.couldNotCheck("no controls or chrome were on screen in \(pose)"))
        }
        if !samples.contains(where: { $0.statusBar != nil }), samples.count >= 3 {
            findings.append(.note("the status bar could not be read in \(pose), so only the controls and chrome were watched"))
        }
        let keys = Set(samples.flatMap(\.elements.keys)).count
        return FeelResult.judged(check: FeelGenre.flicker.rawValue,
                                 passing: "still while idle: \(keys) controls held still in \(samples.count) looks \(over)",
                                 failing: { _ in "not still while idle: \(changes) changes \(over)" },
                                 measures: ["samples": Double(samples.count), "elements": Double(keys), "changes": Double(changes),
                                            "seconds": (span * 1000).rounded() / 1000],
                                 findings: findings)
    }
}
