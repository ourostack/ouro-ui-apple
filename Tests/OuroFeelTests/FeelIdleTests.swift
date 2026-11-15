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
