import OuroHX
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
private func target(_ style: OuroHXStyle) -> Double { style.contrast == .increased ? 7 : 4.5 }

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

    @Test func aFadeIsACrossfadeOverBase() {
        #expect(OuroAppearance.fade.step(reduceMotion: true) == .crossfade(duration: OuroTokens.Duration.base))
        #expect(OuroAppearance.move(edge: .bottom).step(reduceMotion: false) == OuroMotion.step(.spring, reduceMotion: false))
    }
}

// MARK: announce.urgency

@Suite struct AnnouncementTests {
    /// As on web: a destructive or warning banner is `role="alert"`; a toast interrupts only when destructive.
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
