@testable import OuroHX
import SwiftUI
import Testing

/// Every theme in every mode the components are seen in.
private let styles: [(String, OuroHXStyle)] = OuroThemeName.allCases.flatMap { name in
    [ColorScheme.light, .dark].flatMap { scheme in
        [ColorSchemeContrast.standard, .increased].map { contrast in
            ("\(name.rawValue) \(scheme == .dark ? "dark" : "light")\(contrast == .increased ? " increased" : "")",
             OuroHXStyle(theme: OuroTokens.theme(name), scheme: scheme, contrast: contrast))
        }
    }
}

private func ratio(_ a: Color.Resolved, _ b: Color.Resolved) -> Double { OuroColor.contrastRatio(a, b) }
/// 5:1, a margin over WCAG's 4.5, or 7:1 under increased contrast. Xcode's audit measures antialiased pixels and read
/// a soft button's label and a banner's description at exactly 4.5:1 as "Contrast nearly passed".
private func target(_ style: OuroHXStyle) -> Double { style.contrast == .increased ? 7 : 5 }

// MARK: target.touch

@Suite struct TouchTargetTests {
    @Test(arguments: OuroButtonSize.allCases)
    func everyButtonSizeIs44PointsOnATouchScreen(size: OuroButtonSize) {
        #expect(size.minimumHeight(on: .touch) >= 44)
        #expect(OuroButtonSize.minimumTarget(on: .touch) == 44)
    }

    @Test func aPointerGetsDesktopDensity() {
        #expect(OuroButtonSize.sm.minimumHeight(on: .pointer) == 28)
        #expect(OuroButtonSize.md.minimumHeight(on: .pointer) == 32)
        #expect(OuroButtonSize.lg.minimumHeight(on: .pointer) == 40)
    }

    @Test func theCurrentPlatformIsTouchOnIOS() {
        #if os(iOS) || os(visionOS)
        #expect(OuroInput.current == .touch)
        #else
        #expect(OuroInput.current == .pointer)
        #endif
    }

    @Test func closeAndDismissControlsAre44Points() {
        #expect(OuroBannerMetrics.dismissTarget >= 44)
        #expect(OuroToastMetrics.dismissTarget >= 44)
        #expect(OuroSheetMetrics.closeTarget >= 44)
    }

    /// iOS 26 and later draw a sheet below its full height at 96% (measured: a 44-point button reads 42.2 in the
    /// gallery's UI tests). Inside `.ouroSheet`, controls are sized up so they are still 44 points as drawn.
    @Test func aSheetsControlsAre44PointsAsDrawn() {
        #expect(OuroSheetMetrics.closeTarget * OuroSheetMetrics.drawnScale >= 44)
        #expect(OuroSheetMetrics.touchTarget * OuroSheetMetrics.drawnScale >= 44)
        for size in OuroButtonSize.allCases {
            #expect(size.minimumHeight(on: .touch, target: OuroSheetMetrics.touchTarget) * OuroSheetMetrics.drawnScale >= 44)
        }
        #expect(OuroButtonSize.md.minimumHeight(on: .touch, target: 44) == 44)
        #expect(OuroButtonSize.lg.minimumHeight(on: .touch, target: OuroSheetMetrics.touchTarget) == 48)
        #expect(OuroButtonSize.sm.minimumHeight(on: .pointer, target: OuroSheetMetrics.touchTarget) == 28)
    }
}

// MARK: contrast.text

@Suite struct ContrastTests {
    @Test(arguments: OuroButtonVariant.allCases)
    func everyButtonLabelReadsOnItsFillInEveryThemeAndMode(variant: OuroButtonVariant) {
        for (name, style) in styles {
            for tone in OuroTone.allCases {
                let p = OuroButtonPalette(tone: tone, variant: variant, style: style)
                #expect(ratio(p.label, p.surface) >= target(style), "\(name) \(tone) \(variant): \(ratio(p.label, p.surface))")
            }
        }
    }

    @Test func bannerTextAndIconReadInEveryThemeAndMode() {
        for (name, style) in styles {
            for tone in OuroTone.allCases {
                let p = OuroBannerPalette(tone: tone, style: style)
                #expect(ratio(p.title, p.surface) >= target(style), "\(name) \(tone) title")
                #expect(ratio(p.description, p.surface) >= target(style), "\(name) \(tone) description")
                #expect(ratio(p.icon, p.surface) >= target(style), "\(name) \(tone) icon")
            }
        }
    }

    @Test func toastTextAndIconReadInEveryThemeAndMode() {
        for (name, style) in styles {
            for tone in OuroTone.allCases {
                let p = OuroToastPalette(tone: tone, style: style)
                #expect(ratio(p.message, p.surface) >= target(style), "\(name) \(tone) message")
                #expect(ratio(p.description, p.surface) >= target(style), "\(name) \(tone) description")
                #expect(ratio(p.icon, p.surface) >= target(style), "\(name) \(tone) icon")
            }
        }
    }

    @Test func emptyStateAndSheetTextReadInEveryThemeAndMode() {
        for (name, style) in styles {
            let e = OuroEmptyStatePalette(style: style)
            #expect(ratio(e.title, e.surface) >= target(style), "\(name) empty title")
            #expect(ratio(e.description, e.surface) >= target(style), "\(name) empty description")
            let s = OuroSheetPalette(style: style)
            #expect(ratio(s.title, s.surface) >= target(style), "\(name) sheet title")
            #expect(ratio(s.description, s.surface) >= target(style), "\(name) sheet description")
        }
    }

    @Test func aSolidButtonKeepsItsThemeColoursWhereTheyAlreadyRead() {
        let style = OuroHXStyle(theme: OuroTokens.pearl, scheme: .light)
        let p = OuroButtonPalette(tone: .primary, variant: .solid, style: style)
        #expect(ratio(p.surface, style.colors.primary.resolve(in: EnvironmentValues())) < 1.01)
    }
}

// MARK: motion.reduced

@Suite struct ComponentMotionTests {
    @Test func nothingMovesUnderReduceMotion() {
        #expect(OuroToastMetrics.appearance(reduceMotion: false) == .move(edge: .bottom))
        #expect(OuroToastMetrics.appearance(reduceMotion: true) == .fade)
        #expect(OuroBannerMetrics.appearance(reduceMotion: false) == .move(edge: .top))
        #expect(OuroBannerMetrics.appearance(reduceMotion: true) == .fade)
        #expect(OuroSheetMetrics.presentation(reduceMotion: false) == .move(edge: .bottom))
        #expect(OuroSheetMetrics.presentation(reduceMotion: true) == .fade)
        #expect(OuroButtonMetrics.pressScale(isPressed: true, reduceMotion: true) == 1)
        #expect(OuroButtonMetrics.pressScale(isPressed: true, reduceMotion: false) == OuroTokens.Press.scale)
    }

    /// Opening and closing (the close button too) go through one transaction, without animation under Reduce Motion.
    @Test func aSheetOpensAndClosesWithoutAnimationUnderReduceMotion() {
        #expect(OuroSheetMetrics.transaction(reduceMotion: true).disablesAnimations)
        #expect(!OuroSheetMetrics.transaction(reduceMotion: false).disablesAnimations)
    }

    @Test func aFadeIsACrossfadeOverBase() {
        #expect(OuroAppearance.fade.step(reduceMotion: true) == .crossfade(duration: OuroTokens.Duration.base))
        #expect(OuroAppearance.move(edge: .bottom).step(reduceMotion: false) == OuroMotion.step(.spring, reduceMotion: false))
    }
}

// MARK: announce.urgency

@Suite struct AnnouncementTests {
    /// As on web: a destructive or warning banner is `role="alert"`; a toast interrupts only when destructive.
    @Test func aBannerSpeaksOnArrivalAndWhenItsWordsChange() {
        #expect(OuroBannerMetrics.announces("Couldn't save", after: nil))
        #expect(!OuroBannerMetrics.announces("Couldn't save", after: "Couldn't save"))
        #expect(OuroBannerMetrics.announces("Saved", after: "Couldn't save"))
    }

    @Test(arguments: OuroTone.allCases)
    func destructiveAndWarningBannersInterruptOnlyDestructiveToastsDo(tone: OuroTone) {
        #expect(tone.announcementPriority(for: .banner) == ((tone == .destructive || tone == .warning) ? .high : .default))
        #expect(tone.announcementPriority(for: .toast) == (tone == .destructive ? .high : .default))
    }

    @Test func aBannerAndAToastSayTheirWords() {
        #expect(OuroBannerMetrics.announcement(title: "Couldn't save", description: "Check your connection.") == "Couldn't save. Check your connection.")
        #expect(OuroBannerMetrics.announcement(title: "Saved", description: nil) == "Saved")
        let toast = OuroToast("Recipe saved", tone: .success)
        #expect(toast.announcement == "Recipe saved")
    }

    @Test func tonesHaveTheirHaptics() {
        #expect(OuroTone.success.haptic == .finished)
        #expect(OuroTone.warning.haptic == .warned)
        #expect(OuroTone.destructive.haptic == .failed)
        #expect(OuroTone.primary.haptic == nil)
        #expect(OuroTone.secondary.haptic == nil)
    }
}

// MARK: toast.action-stays and the queue

@Suite struct ToastTests {
    @Test func aToastWithAnActionStaysUntilDismissed() {
        let undo = OuroToastAction("Undo") {}
        #expect(OuroToast("Deleted", action: undo).seconds == nil)
        #expect(OuroToast("Deleted", action: undo, duration: .seconds(8)).seconds == 8)
        #expect(OuroToast("Saved").seconds == 5)
        #expect(OuroToast("Saved", duration: .untilDismissed).seconds == nil)
        #expect(OuroToast("Saved", duration: .seconds(0)).seconds == nil)
    }

    @Test func upToThreeShowAndTheRestWaitWithDestructiveFirst() {
        var q = OuroToastQueue()
        for i in 1...4 { q.show(OuroToast("t\(i)", id: "t\(i)")) }
        q.show(OuroToast("bad", tone: .destructive, id: "bad"))
        #expect(q.visible.map(\.id) == ["t1", "t2", "t3"])
        #expect(q.waiting.map(\.id) == ["bad", "t4"])
        q.dismiss("t2")
        #expect(q.visible.map(\.id) == ["t1", "t3", "bad"])
        q.dismiss()
        #expect(q.visible.isEmpty && q.waiting.isEmpty)
    }

    /// At the accessibility text sizes one toast is as tall as a third of the screen, so only one shows at a time and
    /// the rest wait their turn in order; the page under them stays readable.
    @Test func atAccessibilitySizesOneToastShowsAndTheRestWait() {
        #expect(OuroToastMetrics.maximumVisible(accessibilitySize: false) == 3)
        #expect(OuroToastMetrics.maximumVisible(accessibilitySize: true) == 1)
        var q = OuroToastQueue()
        for i in 1...3 { q.show(OuroToast("t\(i)", id: "t\(i)")) }
        q.limit = 1
        #expect(q.visible.map(\.id) == ["t1"])
        #expect(q.waiting.map(\.id) == ["t2", "t3"])
        q.show(OuroToast("t4", id: "t4"))
        #expect(q.visible.map(\.id) == ["t1"])
        q.dismiss("t1")
        #expect(q.visible.map(\.id) == ["t2"])
        q.limit = 3
        #expect(q.visible.map(\.id) == ["t2", "t3", "t4"])
        #expect(q.waiting.isEmpty)
    }

    /// "Saving" replaced by "Saved" under the same id is a new showing: it is announced and its countdown starts over.
    @Test func aReplacementIsANewShowing() {
        var q = OuroToastQueue()
        let saving = OuroToast("Saving", duration: .untilDismissed, id: "s")
        q.show(saving)
        let saved = OuroToast("Saved", tone: .success, id: "s")
        q.show(saved)
        #expect(q.visible.map(\.id) == ["s"])
        #expect(q.visible[0].showing == saved.showing)
        #expect(saving.showing != saved.showing)
        #expect(q.visible[0].seconds == OuroToastMetrics.defaultSeconds)
    }

    /// The countdown waits while VoiceOver or Switch Control is on the toast, or a pointer is over it, as web pauses on
    /// focus and hover; it starts over when they leave.
    @Test func theCountdownWaitsWhileSomeoneIsOnTheToast() {
        let saved = OuroToast("Saved")
        #expect(OuroToastMetrics.countdown(for: saved, held: false) == OuroToastMetrics.defaultSeconds)
        #expect(OuroToastMetrics.countdown(for: saved, held: true) == nil)
    }

    /// A toast shows above a sheet: the newest open sheet hosts the toasts, and the root hosts them when none is open.
    @MainActor @Test func toastsShowAboveTheNewestSheet() {
        let model = OuroToastModel()
        #expect(model.hosts(nil))
        let sheet = UUID(), inner = UUID()
        model.enter(sheet)
        #expect(!model.hosts(nil) && model.hosts(sheet))
        model.enter(inner)
        #expect(!model.hosts(sheet) && model.hosts(inner))
        model.leave(inner)
        #expect(model.hosts(sheet))
        model.leave(sheet)
        #expect(model.hosts(nil))
    }

    /// A toast moving between hosts (a sheet opening or closing) is the same showing: VoiceOver hears it and its
    /// haptic plays once, and its countdown carries on rather than starting over.
    @MainActor @Test func aToastMovingBetweenHostsIsHeardOnceAndKeepsItsTime() {
        let model = OuroToastModel()
        let saved = OuroToast("Saved")
        #expect(model.arrives(saved.showing))
        #expect(!model.arrives(saved.showing))
        let start = Date(timeIntervalSince1970: 1000)
        #expect(model.remaining(for: saved, held: false, now: start) == OuroToastMetrics.defaultSeconds)
        #expect(model.remaining(for: saved, held: false, now: start + 2) == OuroToastMetrics.defaultSeconds - 2)
        #expect(model.remaining(for: saved, held: true, now: start + 3) == nil)
        #expect(model.remaining(for: saved, held: false, now: start + 4) == OuroToastMetrics.defaultSeconds)
        #expect(model.remaining(for: OuroToast("Undo me", action: OuroToastAction("Undo") {}), held: false, now: start) == nil)
    }

    /// A toast sent back to wait (the limit falling to one at the accessibility sizes) shows afresh when its turn
    /// comes: announced again, with its full time.
    @MainActor @Test func aToastSentBackToWaitShowsAfresh() {
        let model = OuroToastModel()
        let a = OuroToast("A", id: "a"), b = OuroToast("B", id: "b")
        model.queue.show(a)
        model.queue.show(b)
        let start = Date(timeIntervalSince1970: 1000)
        _ = model.arrives(b.showing)
        _ = model.remaining(for: b, held: false, now: start)
        model.setLimit(1)
        #expect(model.queue.waiting.map(\.id) == ["b"])
        #expect(model.arrives(b.showing))
        #expect(model.remaining(for: b, held: false, now: start + 4) == OuroToastMetrics.defaultSeconds)
    }

    @Test func aToastsBorderReadsUnderIncreasedContrast() {
        for (name, style) in styles where style.contrast == .increased {
            let p = OuroToastPalette(tone: .secondary, style: style)
            #expect(ratio(p.border, p.surface) >= OuroColor.increasedLineContrast, "\(name) toast border")
        }
    }

    @Test func aToastWithTheIdOfOneShowingReplacesItInPlace() {
        var q = OuroToastQueue()
        q.show(OuroToast("Saving", id: "s"))
        q.show(OuroToast("Other", id: "o"))
        q.show(OuroToast("Saved", tone: .success, id: "s"))
        #expect(q.visible.map(\.message) == ["Saved", "Other"])
    }

    @Test func dismissingAWaitingToastMeansItNeverShows() {
        var q = OuroToastQueue()
        for i in 1...4 { q.show(OuroToast("t\(i)", id: "t\(i)")) }
        q.dismiss("t4")
        q.dismiss("t1")
        #expect(q.visible.map(\.id) == ["t2", "t3"])
    }

    @Test func toastsGetTheirOwnIds() {
        #expect(OuroToast("a").id != OuroToast("a").id)
    }
}

// MARK: The shared tone vocabulary matches web's

@Suite struct ToneTests {
    @Test func tonesAreWebsTones() {
        #expect(OuroTone.allCases.map(\.rawValue) == ["primary", "secondary", "destructive", "success", "warning"])
        #expect(OuroButtonVariant.allCases.map(\.rawValue) == ["solid", "soft", "outline", "plain", "glass"])
        #expect(OuroButtonSize.allCases.map(\.rawValue) == ["sm", "md", "lg"])
    }

    @Test func bannerAndToastIconsFollowWeb() {
        #expect(OuroTone.success.systemImage(for: .toast) == "checkmark.circle.fill")
        #expect(OuroTone.secondary.systemImage(for: .toast) == nil)
        #expect(OuroTone.secondary.systemImage(for: .banner) != nil)
        for tone in OuroTone.allCases { #expect(tone.systemImage(for: .banner) != nil) }
    }
}

// MARK: role

@Suite struct ButtonRoleTests {
    /// `Button(role: .destructive)` draws in the destructive tone unless another tone than primary was asked for.
    @Test func aDestructiveRoleDrawsDestructive() {
        #expect(OuroButtonStyle(.solid).resolvedTone(for: .destructive) == .destructive)
        #expect(OuroButtonStyle(.soft).resolvedTone(for: .destructive) == .destructive)
        #expect(OuroButtonStyle(.solid).resolvedTone(for: nil) == .primary)
        #expect(OuroButtonStyle(.solid).resolvedTone(for: .cancel) == .primary)
        #expect(OuroButtonStyle(.solid, tone: .secondary).resolvedTone(for: .destructive) == .secondary)
    }
}
