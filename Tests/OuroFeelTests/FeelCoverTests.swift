import CoreGraphics
import Foundation
import OuroFeelCore
import Testing

private let phone = CGRect(x: 0, y: 0, width: 402, height: 874)
private let statusBar = FeelElement(key: "status bar", type: "status bar", frame: CGRect(x: 0, y: 0, width: 402, height: 54))

private func text(_ key: String, _ y: CGFloat, height: CGFloat = 22) -> FeelElement {
    FeelElement(key: key, type: "text", frame: CGRect(x: 24, y: y, width: 354, height: height))
}

@Suite struct CoverTests {
    @Test func aHeaderAboveTheTextPasses() {
        let header = FeelElement(key: "header", type: "text", frame: CGRect(x: 24, y: 60, width: 354, height: 20))
        let result = FeelCover.check(content: [text("line 1", 88), text("line 2", 112)], chrome: [header],
                                     keepClear: [statusBar], window: phone, pose: "portrait")
        #expect(result.passed, "\(result.text)")
        #expect(result.check == FeelGenre.insideWindow.rawValue)
        #expect(result.measures["content"] == 2)
    }

    @Test func aHeaderOverTheFirstLineFails() {
        // As Gatefold build 39's running head sat over the first line on the folded Duo.
        let header = FeelElement(key: "header", type: "text", frame: CGRect(x: 24, y: 60, width: 354, height: 20))
        let result = FeelCover.check(content: [text("line 1", 70), text("line 2", 100)], chrome: [header],
                                     keepClear: [statusBar], window: phone, pose: "portrait")
        #expect(!result.passed)
        #expect(result.detections.count == 1)
        #expect(result.detections[0].what.contains("\"header\" covers"))
        #expect(result.detections[0].what.contains("\"line 1\""))
        #expect(result.detections[0].what.contains("portrait"))
    }

    @Test func aTouchAtTheEdgeIsNotACover() {
        // Frames that share an edge, or overlap by under a point (rounding), do not cover each other.
        let header = FeelElement(key: "header", type: "text", frame: CGRect(x: 24, y: 60, width: 354, height: 20.6))
        #expect(FeelCover.check(content: [text("line 1", 80)], chrome: [header], window: phone, pose: "p").passed)
    }

    @Test func chromeUnderTheStatusBarFails() {
        let bar = FeelElement(key: "reader.close", type: "button", frame: CGRect(x: 8, y: 20, width: 44, height: 44))
        let result = FeelCover.check(content: [text("line 1", 120)], chrome: [bar], keepClear: [statusBar], window: phone,
                                     pose: "open, portrait")
        #expect(!result.passed)
        #expect(result.detections.count == 1)
        #expect(result.detections[0].what.contains("under the status bar"))
    }

    @Test func textScrolledUnderTheStatusBarIsFine() {
        // Content may scroll under the status bar; only chrome must keep clear of it.
        #expect(FeelCover.check(content: [text("line 0", 30), text("line 1", 60)], chrome: [], keepClear: [statusBar],
                                window: phone, pose: "p").passed)
    }

    @Test func contentOutsideTheWindowIsNotJudgedHere() {
        // A paginated book's next column sits past the side; inside-the-window judges where things are, not this check.
        let header = FeelElement(key: "header", type: "text", frame: CGRect(x: 24, y: 60, width: 354, height: 20))
        let offside = FeelElement(key: "next column", type: "text", frame: CGRect(x: 426, y: 60, width: 354, height: 22))
        #expect(FeelCover.check(content: [offside, text("line 1", 88)], chrome: [header], window: phone, pose: "p").passed)
    }

    @Test func noContentCouldNotBeChecked() {
        let header = FeelElement(key: "header", type: "text", frame: CGRect(x: 24, y: 60, width: 354, height: 20))
        let result = FeelCover.check(content: [], chrome: [header], window: phone, pose: "portrait")
        #expect(!result.passed)
        #expect(result.detections.isEmpty)
        #expect(result.summary.hasPrefix("could not check"))
    }

    @Test func noChromeCouldNotBeChecked() {
        // A header that never showed was not judged, so the check cannot pass on it.
        let result = FeelCover.check(content: [text("line 1", 88)], chrome: [], window: phone, pose: "portrait", expected: ["header"])
        #expect(!result.passed)
        #expect(result.summary.contains("\"header\""))
    }

    @Test func posesCombine() {
        let header = FeelElement(key: "header", type: "text", frame: CGRect(x: 24, y: 60, width: 354, height: 20))
        let good = FeelCover.check(content: [text("line 1", 88)], chrome: [header], window: phone, pose: "closed")
        let bad = FeelCover.check(content: [text("line 1", 70)], chrome: [header], window: phone, pose: "open")
        let both = FeelCover.combine([good, bad])
        #expect(!both.passed)
        #expect(both.summary.contains("1 of 2 poses"))
        #expect(FeelCover.combine([good, good]).passed)
    }
}
