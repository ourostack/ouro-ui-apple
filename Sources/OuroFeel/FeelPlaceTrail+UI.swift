#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
public import CoreGraphics
public import OuroFeelCore
public import XCTest

/// One step of a place trail, and whether it is a move meant to change the place.
@MainActor
public struct FeelPlaceMove {
    public let step: FeelPlaceStep
    public let deliberate: Bool

    public init(_ step: FeelPlaceStep, deliberate: Bool) {
        self.step = step
        self.deliberate = deliberate
    }

    /// A move of yours: a page turn, a jump to a chapter.
    public static func move(_ step: FeelPlaceStep) -> FeelPlaceMove { FeelPlaceMove(step, deliberate: true) }
    /// An action that must keep the place.
    public static func stray(_ step: FeelPlaceStep) -> FeelPlaceMove { FeelPlaceMove(step, deliberate: false) }
}

extension OuroFeel {
    // MARK: Place trails

    /// Reads the place once it is steady, then runs each move and reads the place `reads` times after it, running
    /// `between` before each read (by default a quarter-second pause; a fixture on its own clock advances it a tick and
    /// waits for the app to show it). Only fingerprints are kept (``FeelPlace/fingerprint(_:)``), never the text. The
    /// checks on a trail judge it in reads, never in seconds: ``FeelPlaceTrail/strayInput()`` and
    /// ``FeelPlaceTrail/fights(hold:)``.
    public func placeTrail(_ moves: [FeelPlaceMove], reads: Int = 5, between: (() -> Void)? = nil,
                           read: (() -> String)? = nil) -> FeelPlaceTrail {
        let read = read ?? { app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n") }
        var trail = FeelPlaceTrail()
        trail.read(FeelPlace.fingerprint(steady(read)))
        for move in moves {
            trail.act(move.step.name, deliberate: move.deliberate)
            move.step.run(self)
            for _ in 0..<max(1, reads) {
                if let between { between() } else { pause(0.25) }
                trail.read(FeelPlace.fingerprint(read()))
            }
        }
        return trail
    }

    /// Place kept through stray input: runs each step as a stray action (``FeelPlaceStep/stray`` by default: a tap in
    /// the middle, an edge swipe, a trip to the Home Screen) and fails if any moved the place at any of the `reads`
    /// reads after it. Read the place with something that names it (a location, a page number) or with the words on
    /// screen; only their fingerprint is reported.
    public func placeHeld(across steps: [FeelPlaceStep] = FeelPlaceStep.stray, reads: Int = 4, between: (() -> Void)? = nil,
                          read: (() -> String)? = nil) -> FeelResult {
        placeTrail(steps.map(FeelPlaceMove.stray), reads: reads, between: between, read: read).strayInput()
    }

    /// Navigation that fights you: runs each of your moves and reads the place `reads` times after it. The place must
    /// land (two reads in a row agree) and then hold for `hold` reads with no late restore, re-sent jump or sync landing
    /// moving it again. Give `reads` enough reads to outlast the app's restore or sync.
    public func placeFights(_ moves: [FeelPlaceStep], reads: Int = 6, hold: Int = 3, between: (() -> Void)? = nil,
                            read: (() -> String)? = nil) -> FeelResult {
        placeTrail(moves.map(FeelPlaceMove.move), reads: reads, between: between, read: read).fights(hold: hold)
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

    /// Opens a sheet (or any card that a swipe down closes) with `open`, then swipes it away without choosing anything.
    public static func sheetDismissed(_ name: String, open: @escaping @MainActor (XCUIApplication) -> Void) -> FeelPlaceStep {
        FeelPlaceStep("\(name) opened and swiped away") { feel in
            open(feel.app)
            feel.pause(1)
            feel.swipeDown()
            feel.pause(1)
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
