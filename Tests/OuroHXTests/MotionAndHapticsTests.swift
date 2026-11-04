import OuroHX
import SwiftUI
import Testing

@Suite struct MotionTests {
    @Test func stepsComeFromCoreTokens() {
        #expect(OuroMotion.step(.spring, reduceMotion: false) == .spring(visualDuration: 0.4, bounce: 0.15))
        #expect(OuroMotion.step(.fast, reduceMotion: false) == .curve(OuroTokens.Ease.out, duration: 0.15))
        #expect(OuroMotion.step(.base, reduceMotion: false) == .curve(OuroTokens.Ease.out, duration: 0.2))
        #expect(OuroMotion.step(.slow, reduceMotion: false) == .curve(OuroTokens.Ease.inOut, duration: 0.3))
        #expect(OuroMotion.step(.press, reduceMotion: false) == .curve(OuroTokens.Ease.out, duration: 0.16))
        #expect(OuroMotion.step(.sheet, reduceMotion: false) == .curve(OuroTokens.Ease.drawer, duration: 0.5))
        #expect(OuroMotion.step(.draw, reduceMotion: false) == .curve(OuroTokens.Ease.out, duration: 0.24))
    }

    @Test(arguments: OuroMotion.Kind.allCases)
    func reduceMotionCrossfadesEverythingButPress(kind: OuroMotion.Kind) {
        let step = OuroMotion.step(kind, reduceMotion: true)
        if kind == .press {
            #expect(step == .none)
        } else {
            #expect(step == .crossfade(duration: OuroTokens.Duration.base))
        }
        #expect(OuroMotion.step(kind, reduceMotion: true).animation == nil || step != .none)
    }

    @Test func pressScalesOnlyWithMotion() {
        #expect(OuroMotion.pressScale(isPressed: true, reduceMotion: false) == 0.97)
        #expect(OuroMotion.pressScale(isPressed: true, reduceMotion: true) == 1)
        #expect(OuroMotion.pressScale(isPressed: false, reduceMotion: false) == 1)
    }
}

@Suite struct HapticsTests {
    @Test func theTableNamesEachMomentOnce() {
        let names = OuroHaptics.table.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names == ["selected", "checked", "stepped", "turned", "started", "finished", "warned", "failed"])
    }

    @Test func momentsMapToFeedback() {
        #expect(OuroHapticMoment.checked.feedback == .selection)
        #expect(OuroHapticMoment.turned.feedback == .impact(weight: .light, intensity: 0.7))
        #expect(OuroHapticMoment.started.feedback == .impact(weight: .medium, intensity: 1))
        #expect(OuroHapticMoment.finished.feedback == .success)
        #expect(OuroHapticMoment.warned.feedback == .warning)
        #expect(OuroHapticMoment.failed.feedback == .error)
        #expect(OuroHapticMoment(name: "custom", feedback: .selection).name == "custom")
    }

    /// The gallery and docs name a feedback the way a person would, never as a Swift value dump (#9).
    @Test func feedbackHasAHumanName() {
        #expect(OuroHapticMoment.Feedback.selection.label == "Selection")
        #expect(OuroHapticMoment.Feedback.impact(weight: .light, intensity: 0.7).label == "Light impact, 70%")
        #expect(OuroHapticMoment.Feedback.impact(weight: .medium, intensity: 1).label == "Medium impact")
        #expect(OuroHapticMoment.Feedback.impact(weight: .heavy, intensity: 0.5).label == "Heavy impact, 50%")
        #expect(OuroHapticMoment.Feedback.success.label == "Success")
        #expect(OuroHapticMoment.Feedback.warning.label == "Warning")
        #expect(OuroHapticMoment.Feedback.error.label == "Error")
        for moment in OuroHaptics.table {
            #expect(!moment.feedback.label.contains("OuroHX"), "\(moment.name): \(moment.feedback.label)")
            #expect(String(describing: moment.feedback) == moment.feedback.label)
        }
    }

    @Test @MainActor func playingWithoutAnEngineIsANoOp() {
        #if os(macOS)
        #expect(OuroHaptics.play(.checked) == false)
        #endif
    }
}
