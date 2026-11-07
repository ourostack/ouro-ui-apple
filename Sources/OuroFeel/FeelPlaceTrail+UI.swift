#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
public import CoreGraphics
public import OuroFeelCore
public import XCTest

/// One step of a place trail: whether it is a move meant to change the place, and where you chose to land.
@MainActor
public struct FeelPlaceMove {
    public let step: FeelPlaceStep
    public let deliberate: Bool
    /// What `read` returns at the place this move must land on (a chapter picked from Contents); nil when any landing
    /// is yours to keep.
    public let landsOn: String?

    public init(_ step: FeelPlaceStep, deliberate: Bool, landsOn: String? = nil) {
        self.step = step
        self.deliberate = deliberate
        self.landsOn = landsOn
    }

    /// A move of yours: a page turn, a jump to a chapter. With `landsOn`, it must land where `read` returns that.
    public static func move(_ step: FeelPlaceStep, landsOn: String? = nil) -> FeelPlaceMove {
        FeelPlaceMove(step, deliberate: true, landsOn: landsOn)
    }
    /// An action that must keep the place.
    public static func stray(_ step: FeelPlaceStep) -> FeelPlaceMove { FeelPlaceMove(step, deliberate: false) }
}

/// Why the step that just ran did not happen as described, set by the step and read by ``OuroFeel/placeTrail``.
@MainActor enum FeelStepProblem {
    static var last: String?
}

extension OuroFeel {
    // MARK: Place trails

    /// Reads the place once it is steady, then runs each move and reads the place `reads` times after it, running
    /// `between` before each read (by default a quarter-second pause; a fixture on its own clock advances it a tick and
    /// waits for the app to show it). Only fingerprints are kept (``FeelPlace/fingerprint(_:)``), never the text. The
    /// checks on a trail judge it in reads, never in seconds: ``FeelPlaceTrail/strayInput()`` and
    /// ``FeelPlaceTrail/fights(hold:)``.
    ///
    /// `read` must name the place and nothing else: a location, a page number, or the page's own words. Reading every
    /// text on screen would count controls a stray tap shows, or a page number that fades, as a moved place. Return an
    /// empty string while the place is loading (a veil, a placeholder); empty reads are skipped.
    public func placeTrail(_ moves: [FeelPlaceMove], reads: Int = 5, between: (() -> Void)? = nil,
                           read: () -> String) -> FeelPlaceTrail {
        var trail = FeelPlaceTrail()
        trail.read(FeelPlace.fingerprint(steady(read)))
        for move in moves {
            trail.act(move.step.name, deliberate: move.deliberate)
            if let landsOn = move.landsOn { trail.chose(FeelPlace.fingerprint(landsOn)) }
            FeelStepProblem.last = nil
            move.step.run(self)
            if let problem = FeelStepProblem.last { trail.unchecked(problem) }
            for _ in 0..<max(1, reads) {
                if let between { between() } else { pause(0.25) }
                trail.read(FeelPlace.fingerprint(read()))
            }
        }
        return trail
    }

    /// Place kept through stray input: runs each step as a stray action (``FeelPlaceStep/stray`` by default: a tap in
    /// the middle, an edge swipe, a trip to the Home Screen; add ``FeelPlaceStep/noInput`` to catch a late reply that
    /// moves the place while you are idle) and fails if any read after one shows another place, even if it came back.
    public func placeHeld(across steps: [FeelPlaceStep] = FeelPlaceStep.stray, reads: Int = 4, between: (() -> Void)? = nil,
                          read: () -> String) -> FeelResult {
        placeTrail(steps.map(FeelPlaceMove.stray), reads: reads, between: between, read: read).strayInput()
    }

    /// Navigation that fights you: runs each of your moves and reads the place `reads` times after it. The place must
    /// land (two reads in a row agree), where you chose when a move says (``FeelPlaceMove/move(_:landsOn:)``), and
    /// hold there: no late restore, re-sent jump, sync landing or input queued during a jump may move it. Give `reads`
    /// enough reads to outlast the app's restore or sync.
    public func placeFights(_ moves: [FeelPlaceMove], reads: Int = 6, hold: Int = 3, between: (() -> Void)? = nil,
                            read: () -> String) -> FeelResult {
        placeTrail(moves, reads: reads, between: between, read: read).fights(hold: hold)
    }

    /// ``placeFights(_:reads:hold:between:read:)`` for moves with no chosen landing.
    public func placeFights(_ steps: [FeelPlaceStep], reads: Int = 6, hold: Int = 3, between: (() -> Void)? = nil,
                            read: () -> String) -> FeelResult {
        placeFights(steps.map { FeelPlaceMove.move($0) }, reads: reads, hold: hold, between: between, read: read)
    }
}

extension FeelPlaceStep {
    /// A tap at `at`, a point as a fraction of the window (the middle by default), as a stray finger lands. On a reader
    /// the middle shows or hides the controls, which must keep the place. Where a tap in the middle is a deliberate
    /// control in your app, pass a point that is not.
    public static func strayTap(at: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> FeelPlaceStep {
        FeelPlaceStep("stray tap at (\(String(format: "%g", at.x)), \(String(format: "%g", at.y)))") { feel in
            let w = feel.windowFrame
            feel.point(w.minX + w.width * at.x, w.minY + w.height * at.y).tap()
        }
    }

    /// An edge swipe in from the leading edge, the way back's own gesture (``OuroFeel/wayBack(from:follow:depth:limit:alsoInsideWindow:)``
    /// sends the same one). Use it on a screen where that swipe is not a way back, such as a book open full screen.
    public static let edgeSwipe = FeelPlaceStep("edge swipe") { feel in feel.edgeSwipe() }

    /// Nothing at all: the reads after it catch a late reply (a cloud sync, a restore) that moves the place while you
    /// are idle.
    public static let noInput = FeelPlaceStep("no input") { _ in }

    /// Opens a sheet with `open`, waits for `sheet` (an identifier or label inside it) to show, then swipes it away
    /// without choosing anything and waits for it to go, trying a slower swipe once (waits of `timeout` × 4 in all, so a
    /// loaded machine has time). A sheet that never opened or never
    /// closed makes the step one that could not be checked, never a pass.
    public static func sheetDismissed(_ name: String, sheet: String,
                                      open: @escaping @MainActor (XCUIApplication) -> Void) -> FeelPlaceStep {
        FeelPlaceStep("\(name) opened and swiped away") { feel in
            let element = feel.app.descendants(matching: .any)[sheet].firstMatch
            open(feel.app)
            guard element.waitForExistence(timeout: feel.timeout * 4) else {
                FeelStepProblem.last = "\"\(sheet)\" never showed, so the sheet did not open"
                return
            }
            feel.swipeDown()
            if !feel.wait(feel.timeout * 2, until: { !element.exists }) {
                feel.swipeDown(slower: true)
                if !feel.wait(feel.timeout * 2, until: { !element.exists }) {
                    FeelStepProblem.last = "\"\(sheet)\" was still on screen after two swipes down, so the sheet did not close"
                }
            }
        }
    }

    #if os(iOS)
    /// A stray tap in the middle, an edge swipe and a trip to the Home Screen.
    public static let stray = [strayTap(), edgeSwipe, background]
    #else
    public static let stray = [strayTap(), edgeSwipe]
    #endif
}
#endif
