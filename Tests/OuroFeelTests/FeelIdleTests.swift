import CoreGraphics
import Foundation
import OuroFeelCore
import Testing

private let close = CGRect(x: 16, y: 60, width: 44, height: 44)

@Suite struct IdleTests {
    @Test func aStillScreenPasses() {
        let samples = (0..<10).map { FeelIdleSample(at: Double($0) * 0.2, elements: ["reader.close": close], statusBar: true) }
        let result = FeelIdle.check(samples, pose: "open, portrait")
        #expect(result.passed, "\(result.text)")
        #expect(result.check == FeelGenre.flicker.rawValue)
        #expect(result.measures["samples"] == 10)
    }

    @Test func chromeThatTakesTurnsWithTheStatusBarFails() {
        // As Gatefold's reader on the open Duo: the close button and the status bar take turns, several times a second.
        let samples = (0..<10).map { (i: Int) -> FeelIdleSample in
            let elements: [String: CGRect] = i % 2 == 0 ? ["reader.close": close] : [:]
            return FeelIdleSample(at: Double(i) * 0.2, elements: elements, statusBar: i % 2 == 1)
        }
        let result = FeelIdle.check(samples, pose: "open, portrait")
        #expect(!result.passed)
        #expect(result.detections.contains { $0.what.contains("\"reader.close\" appeared or went 9 times") })
        #expect(result.detections.contains { $0.what.contains("status bar showed or hid 9 times") })
    }

    @Test func aControlThatJumpsFails() {
        let moved = close.offsetBy(dx: 300, dy: -40)
        let samples = (0..<6).map { (i: Int) -> FeelIdleSample in
            let frame: CGRect = i % 2 == 0 ? close : moved
            return FeelIdleSample(at: Double(i) * 0.2, elements: ["x": frame], statusBar: nil)
        }
        let result = FeelIdle.check(samples, pose: "p")
        #expect(!result.passed)
        #expect(result.detections.count == 1)
        #expect(result.detections[0].what.contains("\"x\" moved 5 times"))
    }

    @Test func halfAPointIsNotAMove() {
        let samples = (0..<6).map { (i: Int) -> FeelIdleSample in
            let dx: CGFloat = i % 2 == 0 ? 0 : 0.4
            return FeelIdleSample(at: Double(i) * 0.2, elements: ["x": close.offsetBy(dx: dx, dy: 0)], statusBar: nil)
        }
        #expect(FeelIdle.check(samples, pose: "p").passed)
    }

    @Test func tooFewSamplesCouldNotBeChecked() {
        let result = FeelIdle.check([FeelIdleSample(at: 0, elements: ["x": close], statusBar: nil)], pose: "p")
        #expect(!result.passed)
        #expect(result.detections.isEmpty)
    }

    @Test func nothingOnScreenCouldNotBeChecked() {
        let samples = (0..<5).map { FeelIdleSample(at: Double($0) * 0.2, elements: [:], statusBar: nil) }
        #expect(FeelIdle.check(samples, pose: "p").summary.hasPrefix("could not check"))
    }
}

/// A clock that only moves when a look or a pause spends time, so a watch can be fed slow looks.
private final class FakeClock {
    var t = 0.0
    func watch(for seconds: Double, every: Double = 0.1, lookTakes: @escaping (Int) -> Double,
               frame: @escaping (Int) -> CGRect = { _ in close }) -> [FeelIdleSample] {
        var n = 0
        return FeelIdle.watch(for: seconds, every: every, now: { self.t }, look: { at in
            defer { n += 1 }
            self.t += lookTakes(n)
            return FeelIdleSample(at: at, elements: ["reader.page": frame(n)], statusBar: true)
        }, pause: { self.t += $0 })
    }
}

@Suite struct IdleWatchTests {
    static let asOnMain: @Sendable (Int) -> Double = { $0 == 0 ? 4.62 : 5.5 }

    @Test func slowLooksStillGetThreeAndAStillScreenPasses() {
        // Gatefold main, App run 45150534604: a 10 s window sized from a 1.5 s look; the looks then began at 0 and
        // 4.62 s, and the window ran out inside the second, so it took at least 5.4 s: 2 looks, could not check.
        let samples = FakeClock().watch(for: 10, lookTakes: Self.asOnMain)
        let result = FeelIdle.check(samples, pose: "open, portrait")
        #expect(samples.count >= 3, "only \(samples.count) looks")
        #expect(result.passed, "\(result.text)")
    }

    @Test func slowLooksNeverHideAMove() {
        let moved = close.offsetBy(dx: 0, dy: 40)
        let samples = FakeClock().watch(for: 10, lookTakes: Self.asOnMain, frame: { $0 == 2 ? moved : close })
        let result = FeelIdle.check(samples, pose: "open, portrait")
        #expect(!result.passed, "a move in the third look passed: \(result.text)")
        #expect(result.detections.contains { $0.what.contains("\"reader.page\" moved") })
    }

    @Test func aStuckLookEndsAsCouldNotCheckNeverAPass() {
        let clock = FakeClock()
        let samples = clock.watch(for: 10, lookTakes: { _ in 25 })
        let result = FeelIdle.check(samples, pose: "open, portrait")
        #expect(samples.count < 3)
        #expect(clock.t <= 30 + 25, "the watch ran \(clock.t) s")
        #expect(!result.passed && result.text.contains("could not check"), "\(result.text)")
    }

    @Test func quickLooksStillStopAtTheWindow() {
        let clock = FakeClock()
        let samples = clock.watch(for: 3, lookTakes: { _ in 0.05 })
        #expect(samples.count == 30)
        #expect(clock.t < 3.2)
    }
}

/// Gatefold #639's run 46078753578 (duo-feel-closed, testClosedScroll): still while idle failed on a control with no
/// name that appeared once in 9.4 s, with no pixel change in the run's screen recording. Idle judges only what the app
/// draws in its window, and names a nameless control by its kind.
@Suite struct IdleShownTests {
    private let window = CGRect(x: 0, y: 0, width: 466, height: 678)

    @Test func aControlPastTheWindowsEdgeThatComesAndGoesIsNotAChange() {
        // A web view's content past the window's edge, or a pager's next page: in the app, but not drawn.
        let past = CGRect(x: 0, y: 900, width: 200, height: 20)
        let samples = (0..<10).map { i in
            FeelIdleSample(at: Double(i), elements: i < 5 ? ["reader.page": window] : ["reader.page": window, "a link with no name": past],
                           statusBar: false).shown(in: window)
        }
        let result = FeelIdle.check(samples, pose: "closed, scroll")
        #expect(result.passed, "\(result.text)")
    }

    @Test func aControlInTheWindowThatComesAndGoesStillFails() {
        let inside = CGRect(x: 20, y: 300, width: 200, height: 20)
        let samples = (0..<10).map { i in
            FeelIdleSample(at: Double(i), elements: i < 5 ? ["reader.page": window] : ["reader.page": window, "a link with no name": inside],
                           statusBar: false).shown(in: window)
        }
        let result = FeelIdle.check(samples, pose: "closed, scroll")
        #expect(!result.passed)
        #expect(result.detections.first?.what.contains("\"a link with no name\" appeared or went 1 times") == true, "\(result.text)")
    }

    @Test func aWatchedElementThatSlidesOutOfTheWindowIsAChange() {
        let samples = (0..<6).map { i in
            FeelIdleSample(at: Double(i), elements: ["reader.head": i < 3 ? CGRect(x: 0, y: 10, width: 466, height: 20)
                                                                          : CGRect(x: 0, y: -40, width: 466, height: 20)],
                           statusBar: false).shown(in: window)
        }
        #expect(!FeelIdle.check(samples, pose: "closed").passed)
    }

    @Test func noWindowKeepsEverything() {
        let sample = FeelIdleSample(at: 0, elements: ["x": CGRect(x: 0, y: 900, width: 10, height: 10)], statusBar: nil)
        #expect(sample.shown(in: .zero).elements.count == 1)
    }

    @Test func aNamelessControlIsNamedByItsKind() {
        #expect(FeelIdle.unnamed("link") == "a link with no name")
        #expect(FeelIdle.unnamed("button") == "a button with no name")
    }
}

@Suite struct IdleSampleTests {
    private let window = CGRect(x: 0, y: 0, width: 466, height: 678)
    private let onScreen = CGRect(x: 20, y: 300, width: 44, height: 44)
    private let pastEdge = CGRect(x: 20, y: 3000, width: 44, height: 44)

    @Test func aNamelessControlArrivingPastTheEdgeAheadOfOneOnScreenRenamesNothing() {
        // In tree order the newcomer comes first; were it named before it was dropped, the one on screen would become
        // "#2", and the report would say one went and another came.
        let button = FeelIdle.unnamed("button")
        let samples = (0..<8).map { i in
            let found = (i < 4 ? [] : [FeelElement(key: button, type: "button", frame: pastEdge)])
                + [FeelElement(key: button, type: "button", frame: onScreen)]
            return FeelIdle.sample(at: Double(i), found: found, window: window, statusBar: false)
        }
        #expect(samples.allSatisfy { $0.elements == [button: onScreen] })
        #expect(FeelIdle.check(samples, pose: "closed").passed)
    }

    @Test func twoControlsWithOneNameOnScreenAreToldApartByOrder() {
        let sample = FeelIdle.sample(at: 0, found: [FeelElement(key: "Close", type: "button", frame: onScreen),
                                                    FeelElement(key: "Close", type: "button", frame: onScreen.offsetBy(dx: 100, dy: 0))],
                                     window: window, statusBar: nil)
        #expect(sample.elements.keys.sorted() == ["Close", "Close #2"])
    }

    @Test func aControlThatAppearsIsReportedWithWhereItWas() {
        let samples = (0..<6).map { i in
            FeelIdle.sample(at: Double(i), found: i < 3 ? [] : [FeelElement(key: "a link with no name", type: "link", frame: onScreen)],
                            window: window, statusBar: false)
        }
        let result = FeelIdle.check(samples, pose: "closed")
        #expect(result.detections.first?.what.hasSuffix("at x 20, y 300, 44×44 pt") == true, "\(result.text)")
    }
}
