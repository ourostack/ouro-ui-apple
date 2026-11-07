#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
public import CoreGraphics
public import OuroFeelCore
public import XCTest

/// Ouro Feel's driver for a UI test: deterministic checks of how an app feels, one per genre of jank (``FeelGenre``).
///
/// ```swift
/// let feel = OuroFeel(app)
/// feel.expect(feel.insideWindow())                                  // inside the window, in every pose
/// feel.expect(feel.wayBack(from: [.launch]))                       // every reachable screen has a way back
/// ```
///
/// Every check returns a ``FeelResult``; ``expect(_:file:line:)`` attaches its report, writes it to
/// `OURO_FEEL_REPORT_DIR` when set (pass `TEST_RUNNER_OURO_FEEL_REPORT_DIR` to `xcodebuild`), and fails the test when
/// the check did. Checks read frames from accessibility snapshots and never trust `isHittable`, which the simulator
/// grants to points past the window's edge.
@MainActor
public struct OuroFeel {
    public let app: XCUIApplication
    /// How long a step waits for the screen to change or come back.
    public var timeout: TimeInterval = 5

    public init(_ app: XCUIApplication) {
        self.app = app
    }

    public static let clock = "the test runner's wall clock, sampling accessibility snapshots"

    public var environment: FeelEnvironment { FeelEnvironment.current(clock: Self.clock) }

    // MARK: Reports

    /// Records the result (attachment, stdout and `OURO_FEEL_REPORT_DIR`) and fails the test if it failed.
    @discardableResult
    public func expect(_ result: FeelResult, file: StaticString = #filePath, line: UInt = #line) -> FeelResult {
        let result = record(result)
        if !result.passed { XCTFail(result.text, file: file, line: line) }
        return result
    }

    /// Records the result without failing: for a test that expects a check to fail, such as a regression test that
    /// proves the check still catches a known bug.
    @discardableResult
    public func record(_ input: FeelResult, name: String? = nil, film: FeelFilm? = nil) -> FeelResult {
        var result = input
        if result.environment == nil { result.environment = environment }
        let slug = (name ?? result.check).replacingOccurrences(of: " ", with: "-")
        print("[ouro-feel] " + result.text.replacingOccurrences(of: "\n", with: "\n[ouro-feel] "))
        XCTContext.runActivity(named: "Ouro Feel: \(result.check)") { activity in
            let text = XCTAttachment(string: result.text)
            text.name = "ouro-feel-\(slug).txt"
            text.lifetime = .keepAlways
            activity.add(text)
            let json = XCTAttachment(data: result.json, uniformTypeIdentifier: "public.json")
            json.name = "ouro-feel-\(slug).json"
            json.lifetime = .keepAlways
            activity.add(json)
            if let film {
                let raw = XCTAttachment(data: film.json, uniformTypeIdentifier: "public.json")
                raw.name = "ouro-feel-\(slug)-film.json"
                raw.lifetime = .keepAlways
                activity.add(raw)
            }
        }
        if let dir = ProcessInfo.processInfo.environment["OURO_FEEL_REPORT_DIR"], !dir.isEmpty {
            let base = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            try? Data(result.text.utf8).write(to: base.appendingPathComponent("\(slug)-\(stamp).txt"))
            try? result.json.write(to: base.appendingPathComponent("\(slug)-\(stamp).json"))
            if let film { try? film.json.write(to: base.appendingPathComponent("\(slug)-\(stamp)-film.json")) }
        }
        return result
    }

    // MARK: Reading the screen

    static let controlTypes: Set<XCUIElement.ElementType> = [
        .button, .switch, .toggle, .slider, .stepper, .textField, .secureTextField, .searchField, .segmentedControl,
        .link, .cell, .menuButton, .popUpButton, .textView, .picker, .datePicker, .colorWell, .tab, .radioButton, .checkBox,
    ]
    static let scrollTypes: Set<XCUIElement.ElementType> = [.scrollView, .table, .collectionView, .webView]

    /// The app's window and every control in it, from one accessibility snapshot.
    public func controls() -> (window: CGRect, controls: [FeelElement]) {
        guard let root = try? app.snapshot() else { return (.zero, []) }
        let window = Self.mainWindow(root)
        var found: [FeelElement] = []
        // Accessibility does not say which way a scroll view scrolls; a short, wide one whose content runs off its sides
        // is marked sideways; FeelLayout counts it as a carousel only while it is under 60% of the window's height.
        func sideways(_ node: any XCUIElementSnapshot) -> Bool {
            let f = node.frame
            guard f.width > f.height * 1.5 else { return false }
            func extends(_ n: any XCUIElementSnapshot) -> Bool {
                n.children.contains { $0.frame.maxX > f.maxX + 1 || $0.frame.minX < f.minX - 1 || extends($0) }
            }
            return extends(node)
        }
        func walk(_ node: any XCUIElementSnapshot, scroll: CGRect?, across: Bool) {
            let type = node.elementType
            if Self.controlTypes.contains(type), node.isEnabled {
                found.append(FeelElement(key: Self.key(node), type: Self.name(type), frame: node.frame, scroll: scroll,
                                         scrollsHorizontally: across))
            }
            let isScroll = Self.scrollTypes.contains(type)
            for child in node.children {
                walk(child, scroll: isScroll ? node.frame : scroll, across: isScroll ? sideways(node) : across)
            }
        }
        walk(root, scroll: nil, across: false)
        return (window, found)
    }

    /// What is on screen now, keyed by identifier (or label), for the given keys; every element when `keys` is empty.
    public func seen(_ keys: Set<String> = []) -> (window: CGRect, seen: [FeelSeen]) {
        guard let root = try? app.snapshot() else { return (.zero, []) }
        let window = Self.mainWindow(root)
        var found: [FeelSeen] = []
        func walk(_ node: any XCUIElementSnapshot) {
            // Read into values first: Xcode 26's Release build reads the snapshot inside `&&` and `||`'s autoclosures
            // as sending it across isolation, and refuses to compile.
            let type = node.elementType, identifier = node.identifier, label = node.label
            if type != .application && type != .window,
               keys.isEmpty || keys.contains(identifier) || keys.contains(label) {
                found.append(FeelSeen(key: Self.key(node), label: label, frame: node.frame))
            }
            for child in node.children { walk(child) }
        }
        walk(root)
        return (window, found)
    }

    static func key(_ node: any XCUIElementSnapshot) -> String {
        node.identifier.isEmpty ? node.label : node.identifier
    }

    static func name(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .button: "button"
        case .switch, .toggle: "switch"
        case .slider: "slider"
        case .cell: "cell"
        case .link: "link"
        case .textField, .secureTextField, .searchField, .textView: "text field"
        case .segmentedControl: "segmented control"
        case .menuButton, .popUpButton: "menu"
        case .tab: "tab"
        default: "control"
        }
    }

    /// Waits until `condition` holds or `timeout` passes, polling every 0.1 s.
    @discardableResult
    func wait(_ timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    /// The app's main window: the largest. On iPadOS the first window can be a smaller one (seen on the iOS 27.2 iPad
    /// simulator), and measuring against it put the edge swipe mid-screen and the Done button "outside the window".
    static func mainWindow(_ root: any XCUIElementSnapshot) -> CGRect {
        root.children.filter { $0.elementType == .window }.map(\.frame).max { $0.width * $0.height < $1.width * $1.height } ?? root.frame
    }

    /// The main window's frame now.
    var windowFrame: CGRect {
        guard let root = try? app.snapshot() else { return app.windows.firstMatch.frame }
        return Self.mainWindow(root)
    }

    func pause(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    /// A point in app coordinates.
    /// A point in `target`'s coordinates (the app under test unless given; the OS baseline taps Settings).
    func point(_ x: CGFloat, _ y: CGFloat, in target: XCUIApplication? = nil) -> XCUICoordinate {
        (target ?? app).coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    // MARK: Inside the window

    /// Every enabled control's frame lies inside the window, in each pose. On iOS the default turns the device to
    /// landscape and back, checking portrait, landscape and portrait again (the round trip that broke Gatefold build 19).
    public func insideWindow(poses: [FeelPose] = FeelPose.roundTrip) -> FeelResult {
        var results: [FeelResult] = []
        for pose in poses {
            pose.apply(self)
            let (window, found) = controls()
            var result = FeelLayout.check(found, window: window, pose: pose.name)
            #if os(iOS)
            // An app that stays portrait (an iPhone app without landscape) is fine, but say so: its "landscape" was not one.
            if let note = FeelLayout.stayedPortrait(window: window, pose: pose.name, deviceLandscape: pose.orientation?.isLandscape == true) {
                result.findings.append(note)
            }
            #endif
            results.append(result)
        }
        #if os(iOS)
        if poses.contains(where: { $0.orientation != nil }) { FeelPose.portrait.apply(self) }
        #endif
        return FeelLayout.combine(results)
    }

    // MARK: Tap landing

    /// Single taps on `control`, never retried: `trials` at each spot. `.zeroPress` is not a default: on the iOS 27.2
    /// simulator a system `Toggle` ignored XCUITest's zero-length press 3 times in 3, so it measures XCUITest's event,
    /// not the app; add it only for a control that acts on touch-down. A tap lands when `read` (by default the
    /// control's value) changes within `within` seconds (3 by default, since a busy simulator can be slow to report a
    /// change; landing is about whether the tap counted, not how fast); one that has not landed by then gets twice as long
    /// again (three times `within` in all) before it counts as a miss, and a landing in that time is noted as late. With `title`, it also taps the row's title and the gap between title
    /// and control; `rowToggles` says whether those should change the control (a row that acts as one button) or
    /// should not (iOS Settings rows). `baseline` is ``osBaseline(trials:rapid:)``.
    ///
    /// With `rapid` (off by default), that many double taps follow at the control's centre, as a person taps while it
    /// is still animating, each from a settled control (``FeelRapidTaps``). They fit only a control with two states (a
    /// switch, a checkbox), passed as the element itself. `rapidBaseline` is ``osBaseline(trials:rapid:)`` with
    /// `rapid: true`: context in the report only, since every pair must end where it started either way.
    public func tapLanding(
        on control: XCUIElement,
        trials: Int = 5,
        spots: [FeelTapSpot] = [.centre, .leadingEdge, .trailingEdge, .topEdge, .bottomEdge],
        title: XCUIElement? = nil,
        rowToggles: Bool = false,
        baseline: Double? = nil,
        within: Double = 3,
        rapid: Int = 0,
        rapidBaseline: Double? = nil,
        read: (() -> String)? = nil
    ) -> FeelResult {
        guard control.waitForExistence(timeout: timeout), control.frame.width > 0 else {
            return FeelResult(check: FeelGenre.tapLanding.rawValue, passed: false, summary: "could not check: the control to tap was not on screen",
                              findings: [.couldNotCheck("\(control) did not exist or had no size, so no taps were tried")], environment: environment)
        }
        let read = read ?? { (control.value as? String) ?? control.label }
        var results: [FeelTapTrial] = []
        func trial(_ spot: FeelTapSpot, expected: Bool, _ act: () -> Void) {
            let before = read()
            act()
            // Polled here rather than in a closure handed to `wait`: Xcode 26's Release build reads that closure,
            // which holds `read`, as sending it across isolation, and refuses to compile.
            func changed(within timeout: TimeInterval) -> Bool {
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    if read() != before { return true }
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                }
                return read() != before
            }
            var landed = changed(within: within)
            // One tap, never resent. A loaded machine can report a change late, so a tap that should land is given
            // twice as long again before it counts as a miss; one that lands then is noted as late.
            var late = false
            if expected && !landed {
                landed = changed(within: within * 2)
                late = landed
            }
            results.append(FeelTapTrial(spot: spot, landed: landed, expected: expected, late: late))
            // Let the control finish its own animation (a switch's knob slides on after its value flips) before the
            // next tap, as a person would; a tap during it can be swallowed, which is not the target's fault.
            pause(0.6)
        }
        for spot in spots {
            for _ in 0..<trials {
                let f = control.frame
                let inset: CGFloat = 4
                switch spot {
                case .centre: trial(spot, expected: true) { point(f.midX, f.midY).tap() }
                case .leadingEdge: trial(spot, expected: true) { point(f.minX + inset, f.midY).tap() }
                case .trailingEdge: trial(spot, expected: true) { point(f.maxX - inset, f.midY).tap() }
                case .topEdge: trial(spot, expected: true) { point(f.midX, f.minY + inset).tap() }
                case .bottomEdge: trial(spot, expected: true) { point(f.midX, f.maxY - inset).tap() }
                case .zeroPress: trial(spot, expected: true) { point(f.midX, f.midY).press(forDuration: 0) }
                case .title, .gap: break
                }
            }
        }
        if let title {
            for _ in 0..<trials {
                trial(.title, expected: rowToggles) { let t = title.frame; point(t.midX, t.midY).tap() }
                trial(.gap, expected: rowToggles) {
                    let t = title.frame, f = control.frame
                    let knob = f.maxX - min(f.width, 51)
                    point((t.maxX + knob) / 2, f.midY).tap()
                }
            }
        }
        #if os(iOS)
        let centre = control.frame
        let burst: FeelRapidTaps? = rapid > 0
            ? rapidPairs(rapid, at: { point(centre.midX, centre.midY) }, triple: { control.tap(withNumberOfTaps: 3, numberOfTouches: 1) }, read: read)
            : nil
        #else
        let burst: FeelRapidTaps? = nil  // XCUITest's double tap with a touch count is iOS only.
        #endif
        return FeelTaps.evaluate(results, baseline: baseline, rapid: burst, rapidBaseline: rapidBaseline)
    }

    #if os(iOS)
    /// The control's value once it has held still for a second (at least 0.8 s after the taps, at most 6 s): a loaded
    /// machine can apply the second tap of a pair late, and a pair read too early looks as if it lost a tap.
    func settled(_ read: () -> String) -> String {
        pause(0.8)
        var last = read(), still = Date()
        let end = Date().addingTimeInterval(5.2)
        while Date() < end {
            pause(0.2)
            let now = read()
            if now != last { last = now; still = Date() } else if Date().timeIntervalSince(still) >= 1 { break }
        }
        return last
    }

    /// `pairs` double taps at `at`, each from a settled control (``FeelRapidTaps``); one that ends changed is put back
    /// with a single tap. A point, not the element, so the OS baseline can hit a Settings switch's knob (XCUITest gives
    /// that switch the whole row's frame, where a tap does nothing). The same loop serves the app and the baseline.
    /// `triple` (the element's own triple tap; a coordinate has none) runs once after the pairs: ending changed shows
    /// quick taps reach the control. The baseline sends none, since its rate is context only.
    func rapidPairs(_ pairs: Int, at: () -> XCUICoordinate, triple: (() -> Void)? = nil, read: () -> String) -> FeelRapidTaps {
        var same = 0
        for _ in 0..<pairs {
            let start = read()
            at().doubleTap()
            if settled(read) == start {
                same += 1
            } else {
                at().tap()
                _ = settled(read)
            }
        }
        var tripleChanged: Bool?
        if let triple {
            let start = read()
            triple()
            tripleChanged = settled(read) != start
            if tripleChanged == true { at().tap(); _ = settled(read) }
        }
        return FeelRapidTaps(pairs: pairs, endedWhereStarted: same, tripleChanged: tripleChanged)
    }
    #endif

    #if os(iOS)
    /// The same single-tap loop on a switch in the Settings app, on this simulator: how often the simulator itself
    /// delivers a tap. With `rapid`, the double taps ``tapLanding(on:trials:spots:title:rowToggles:baseline:within:rapid:rapidBaseline:read:)``
    /// sends (`trials` pairs), at the switch's knob. Nil when Settings has no reachable switch. It leaves the switch as it found it.
    public func osBaseline(trials: Int = 10, rapid: Bool = false) -> Double? {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        defer { settings.terminate(); app.activate() }
        for path in [["General", "Keyboard"], ["Accessibility", "Touch"]] {
            var ok = true
            for step in path {
                let cell = settings.staticTexts[step].firstMatch
                guard cell.waitForExistence(timeout: 5) else { ok = false; break }
                cell.tap()
            }
            let toggle = settings.switches.firstMatch
            guard ok, toggle.waitForExistence(timeout: 5) else { settings.terminate(); settings.launch(); continue }
            let start = (toggle.value as? String) ?? ""
            if rapid {
                let f = toggle.frame
                let knob = { self.point(f.maxX - min(f.width, 51) / 2, f.midY, in: settings) }
                let burst = rapidPairs(trials, at: knob, read: { (toggle.value as? String) ?? "" })
                if ((toggle.value as? String) ?? "") != start { knob().tap() }
                return burst.rate
            }
            var landed = 0
            for _ in 0..<trials {
                let before = (toggle.value as? String) ?? ""
                let f = toggle.frame
                point(f.maxX - min(f.width, 51) / 2, f.midY, in: settings).tap()
                if wait(1, until: { ((toggle.value as? String) ?? "") != before }) { landed += 1 }
            }
            if ((toggle.value as? String) ?? "") != start {
                let f = toggle.frame
                point(f.maxX - min(f.width, 51) / 2, f.midY, in: settings).tap()
            }
            return Double(landed) / Double(trials)
        }
        return nil
    }
    #endif

    // MARK: Motion

    /// Runs `action`, then samples the elements named in `keys` (identifiers or labels) for `seconds`.
    ///
    /// The film's clock starts just before `action`. XCUITest waits for the app to go idle after a tap, so the first
    /// sample comes when that wait ends: a film sees what happens after an action settles (jumps, late chrome, ghost
    /// copies that stay) and every motion the app starts on its own, but not the frames inside XCUITest's idle wait.
    ///
    /// Samples start `every` seconds apart (default 0.05). Each snapshot holds the app's main thread while it answers,
    /// so sampling back to back can slow the very motion it watches: on the iOS 27.2 simulator a 0.8 s ease sampled
    /// back to back measured 1.84 s.
    public func film(_ keys: [String], for seconds: TimeInterval, every interval: TimeInterval = 0.05,
                     during action: (() -> Void)? = nil) -> FeelFilm {
        let wanted = Set(keys)
        let start = Date()
        action?()
        var frames: [FeelFrame] = []
        var window = CGRect.zero
        var next = 0.0
        while Date().timeIntervalSince(start) < seconds {
            let wait = next - Date().timeIntervalSince(start)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            let now = Date().timeIntervalSince(start)
            next = now + interval
            let (w, seen) = self.seen(wanted)
            if w != .zero { window = w }
            frames.append(FeelFrame(t: now, seen: seen))
        }
        return FeelFilm(window: window, frames: frames)
    }

    /// A film on the app's own clock, which a busy machine cannot thin out. The app keeps a timeline that moves only
    /// when told (`advance`, for example ``FeelClock/darwinNotification(_:)``), one `tick` of seconds at a time, and
    /// shows how many ticks it has taken in the element keyed `clock` (its label, a whole number). The film runs
    /// `action`, samples once, then `steps` times advances the clock and samples once the app shows the new count,
    /// stamping each sample with the app's time. So every sample is exactly one tick apart however slow the machine:
    /// what the app draws between ticks is never part of it, and the app's motion must be a function of its clock.
    ///
    /// Each sample waits for the app's answer, never a fixed time. Only if the app shows no new count for `stall`
    /// seconds does the film end there, with ``FeelFilm/stalledAt`` set, and every motion check on it says it could
    /// not be checked.
    public func film(_ keys: [String], steps: Int, tick: TimeInterval, clock: String, advance: () -> Void,
                     stall: TimeInterval = 30, during action: (() -> Void)? = nil) -> FeelFilm {
        let wanted = Set(keys).union([clock])
        let timedBy = "the app's own clock (\"\(clock)\", \(String(format: "%g", tick)) s a tick), one accessibility snapshot per tick"
        func count(_ seen: [FeelSeen]) -> Int? { seen.first { $0.key == clock }.flatMap { Int($0.label) } }
        // Snapshots until the app shows a count of at least `least`; nil if it shows none for `stall` seconds.
        func sample(atLeast least: Int) -> (window: CGRect, seen: [FeelSeen], count: Int)? {
            let deadline = Date().addingTimeInterval(stall)
            repeat {
                let (w, seen) = self.seen(wanted)
                if let n = count(seen), n >= least { return (w, seen.filter { $0.key != clock }, n) }
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            } while Date() < deadline
            return nil
        }
        action?()
        guard let (w0, first, base) = sample(atLeast: .min) else {
            return FeelFilm(window: .zero, frames: [], stalledAt: 0, timedBy: timedBy)
        }
        var window = w0
        var frames = [FeelFrame(t: 0, seen: first)]
        for step in 1...max(1, steps) {
            advance()
            guard let (w, seen, n) = sample(atLeast: base + step) else {
                return FeelFilm(window: window, frames: frames, stalledAt: Double(step - 1) * tick, timedBy: timedBy)
            }
            if w != .zero { window = w }
            // Stamped with the count the app shows, so a tick the app took on its own is never hidden.
            frames.append(FeelFrame(t: Double(n - base) * tick, seen: seen))
        }
        return FeelFilm(window: window, frames: frames, timedBy: timedBy)
    }

    /// The folder this test process shares with the app's recorder (`OuroFeelRecorder`): the app writes its films here.
    public static let recordDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ouro-feel-record-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    /// What to add to `launchEnvironment` before launching an app that calls `OuroFeelRecorder.installIfRequested()`,
    /// so its recorder listens. The recorder writes into ``recordDirectory``, which a simulator app can reach and an
    /// app on a device cannot (see the README's recorder section).
    public static var recorderEnvironment: [String: String] {
        try? FileManager.default.createDirectory(at: recordDirectory, withIntermediateDirectories: true)
        return [FeelRecording.directoryVariable: recordDirectory.path]
    }

    /// A film the app records itself, one sample per display frame on the app's own display clock, so it holds the
    /// transition `action` starts frame by frame: the frames XCUITest's wait for an idle app hides from
    /// ``film(_:for:every:during:)``. The app must call `OuroFeelRecorder.installIfRequested()` at launch and be launched
    /// with ``recorderEnvironment``. The recorder starts, `action` runs, and the film ends once everything it watches has
    /// held still for half a second after `action` returns (a tap can return while its transition still moves), or at
    /// 20 s, when it is marked stalled.
    ///
    /// Waits only on the app's answers. If the app does not start recording, or writes no film, within `timeout`
    /// seconds, the film is empty and stalled (``FeelFilm/stalledAt``), so every motion check on it could not be checked.
    public func recordedFilm(_ keys: [String], timeout: TimeInterval = 30, during action: () -> Void) -> FeelFilm {
        let timedBy = FeelRecording.timedBy
        let files = FileManager.default
        let dir = Self.recordDirectory
        try? files.createDirectory(at: dir, withIntermediateDirectories: true)
        let request = FeelRecording.Request(keys: keys)
        let recording = dir.appendingPathComponent(FeelRecording.recordingFile(request.id))
        let filmURL = dir.appendingPathComponent(FeelRecording.filmFile(request.id))
        try? JSONEncoder().encode(request).write(to: dir.appendingPathComponent(FeelRecording.requestFile), options: .atomic)
        func waitFor(_ url: URL) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while !files.fileExists(atPath: url.path) {
                if Date() >= deadline { return false }
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            return true
        }
        FeelClock.darwinNotification(FeelRecording.startNotification)()
        guard waitFor(recording) else { return FeelFilm(window: .zero, frames: [], stalledAt: 0, timedBy: timedBy) }
        action()
        FeelClock.darwinNotification(FeelRecording.stopNotification)()
        guard waitFor(filmURL), let data = try? Data(contentsOf: filmURL),
              let film = try? JSONDecoder().decode(FeelFilm.self, from: data) else {
            return FeelFilm(window: .zero, frames: [], stalledAt: 0, timedBy: timedBy)
        }
        return film
    }

    #if !os(visionOS)
    /// Wraps `XCTHitchMetric` (iOS 26 and later) around `action`, `iterations` times. The figures go to the result
    /// bundle, not to a ``FeelResult``. Apple's simulator has reported no hitch figures for the signpost metrics in our
    /// runs, so on a simulator treat a missing figure as "not measured", never as "no hitches".
    @available(iOS 26.0, macOS 26.0, *)
    public func measureHitches(in testCase: XCTestCase, iterations: Int = 3, _ action: () -> Void) {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        testCase.measure(metrics: [XCTHitchMetric(application: app)], options: options, block: action)
    }
    #endif

    // MARK: Place stability

    /// Reads the place (by default every static text on screen, joined) before and after each step and compares
    /// fingerprints. The text never leaves the test; only its SHA-256 prefix goes in the report.
    public func place(across steps: [FeelPlaceStep] = FeelPlaceStep.standard, read: (() -> String)? = nil) -> FeelResult {
        let read = read ?? { app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n") }
        let start = FeelPlace.fingerprint(steady(read))
        var after: [String: String] = [:]
        for step in steps {
            step.run(self)
            after[step.name] = FeelPlace.fingerprint(steady(read))
        }
        return FeelPlace.compare(start: start, after: after)
    }

    /// The reading once it has held still for a second (at most `timeout` × 4).
    func steady(_ read: () -> String) -> String {
        var last = read(), since = Date()
        let deadline = Date().addingTimeInterval(timeout * 4)
        while Date() < deadline {
            pause(0.25)
            let now = read()
            if now != last { last = now; since = Date() }
            if !now.isEmpty && Date().timeIntervalSince(since) >= 1 { break }
        }
        return last
    }
}

/// A device pose for ``OuroFeel/insideWindow(poses:)``.
@MainActor
public struct FeelPose: Sendable {
    public let name: String
    #if os(iOS)
    public let orientation: UIDeviceOrientation?
    #else
    public let orientation: Int?
    #endif

    public static let current = FeelPose(name: "the current pose", orientation: nil)
    #if os(iOS)
    public static let portrait = FeelPose(name: "portrait", orientation: .portrait)
    public static let landscape = FeelPose(name: "landscape", orientation: .landscapeLeft)
    public static let portraitAgain = FeelPose(name: "portrait after landscape", orientation: .portrait)
    public static let landscapeAgain = FeelPose(name: "landscape after portrait", orientation: .landscapeLeft)
    /// Portrait, landscape, then portrait again.
    public static let roundTrip = [portrait, landscape, portraitAgain]
    #else
    public static let roundTrip = [current]
    #endif

    func apply(_ feel: OuroFeel) {
        #if os(iOS)
        guard let orientation, XCUIDevice.shared.orientation != orientation || name.contains("after") else { return }
        let before = feel.windowFrame
        XCUIDevice.shared.orientation = orientation
        feel.wait(3) { feel.windowFrame != before }
        feel.pause(1)
        #endif
    }
}

/// A step for ``OuroFeel/place(across:read:)``.
@MainActor
public struct FeelPlaceStep {
    public let name: String
    let run: @MainActor (OuroFeel) -> Void

    public init(_ name: String, _ run: @escaping @MainActor (OuroFeel) -> Void) {
        self.name = name
        self.run = run
    }

    /// Terminates and launches the app with the same arguments.
    public static let relaunch = FeelPlaceStep("relaunch") { feel in
        feel.app.terminate()
        feel.app.launch()
    }

    #if os(iOS)
    /// Sends the app to the Home Screen for two seconds and brings it back.
    public static let background = FeelPlaceStep("background and return") { feel in
        XCUIDevice.shared.press(.home)
        feel.pause(2)
        feel.app.activate()
    }

    /// Turns to landscape and back to portrait.
    public static let rotate = FeelPlaceStep("rotate and back") { feel in
        FeelPose.landscape.apply(feel)
        FeelPose.portraitAgain.apply(feel)
    }

    public static let standard = [background, rotate, relaunch]
    #else
    public static let standard = [relaunch]
    #endif
}
#endif
