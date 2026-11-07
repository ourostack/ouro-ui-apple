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
/// Distance between two colours in gamma-encoded sRGB, from 0 to about 1.73.
private func distance(_ a: Color.Resolved, _ b: Color.Resolved) -> Double {
    let (r, g, bl) = (Double(a.red - b.red), Double(a.green - b.green), Double(a.blue - b.blue))
    return (r * r + g * g + bl * bl).squareRoot()
}
private func target(_ style: OuroHXStyle) -> Double { style.contrast == .increased ? 7 : 5 }

// MARK: target.touch

@Suite struct TouchTargetTests {
    @Test(arguments: OuroButtonSize.allCases)
    func everyButtonSizeIs44PointsOnATouchScreen(size: OuroButtonSize) {
        #expect(size.minimumHeight(on: .touch) >= 44)
        #expect(OuroButtonSize.minimumTarget(on: .touch) == 44)
    }

    /// Apple's proportions on a touch screen: a small capsule drawn 34 tall inside its 44-point target, a 50-point
    /// default and a 56-point large button. What you see never outgrows what you can press.
    @Test func aSmallButtonIsDrawnSmallerThanItsTarget() {
        #expect(OuroButtonSize.sm.visualHeight(on: .touch, target: 44) == 34)
        #expect(OuroButtonSize.md.visualHeight(on: .touch, target: 44) == 50)
        #expect(OuroButtonSize.lg.visualHeight(on: .touch, target: 44) == 56)
        for size in OuroButtonSize.allCases {
            for input in [OuroInput.touch, .pointer] {
                #expect(size.visualHeight(on: input, target: 44) <= size.minimumHeight(on: input, target: 44))
            }
            #expect(size.visualHeight(on: .pointer, target: 44) == size.minimumHeight(on: .pointer))
        }
    }

    /// A button's default outline is a capsule, as Apple's own buttons are from iOS 26.
    @Test func theDefaultShapeIsACapsule() {
        #expect(OuroButtonStyle().shape == .pill)
    }

    /// A pill stays a capsule at every text size, its ends half its height, up to 44 points, so a label wrapped onto
    /// several lines at the accessibility sizes becomes a rounded rectangle rather than an oval.
    @Test func aPillIsACapsuleAtEveryHeight() {
        #expect(OuroButtonMetrics.pillRadius(height: 34) == 17)
        #expect(OuroButtonMetrics.pillRadius(height: 50) == 25)
        #expect(OuroButtonMetrics.pillRadius(height: 80) == 40)
        #expect(OuroButtonMetrics.pillRadius(height: 140) == 44)
    }

    /// An empty state's symbol is a hero standing alone, and inline in the text beside it.
    @Test func anEmptyStatesSymbolIsCappedAndSmallerInline() {
        #expect(OuroEmptyStateMetrics.symbolSize(alignment: .center) == 60)
        #expect(OuroEmptyStateMetrics.symbolSize(alignment: .leading) == 44)
        #expect(OuroEmptyStateMetrics.maximumSymbolSize == 80)
        #expect(OuroEmptyStateMetrics.descriptionSpacing == 8)
        #expect(OuroEmptyStateMetrics.symbolSpacing == 6)
    }

    /// An empty state arrives in a short cascade: symbol, title, sentence, action, 40 ms apart, each rising 8 points.
    @Test func anEmptyStateArrivesInACascade() {
        #expect(OuroEmptyStateMetrics.arrivalRise == 8)
        #expect(OuroEmptyStateMetrics.arrivalDelay(step: 0) == 0)
        #expect(abs(OuroEmptyStateMetrics.arrivalDelay(step: 3) - 0.12) < 1e-9)
    }

    /// A sheet with one height has nothing to drag between, so it has no grabber; one with several heights shows it.
    @Test func aSheetShowsItsGrabberOnlyWithSeveralHeights() {
        #expect(!OuroSheetMetrics.showsGrabber(detents: nil))
        #expect(!OuroSheetMetrics.showsGrabber(detents: [.medium]))
        #expect(OuroSheetMetrics.showsGrabber(detents: [.medium, .large]))
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

    /// A sheet's close control is drawn at the size of iOS 26's own: a 44-point disc with a 17-point glyph.
    @Test func aSheetsCloseIsIOS26Sized() {
        #expect(OuroSheetMetrics.closeDisc == 44)
        #expect(OuroSheetMetrics.closeGlyph == 17)
        #expect(OuroSheetMetrics.closeDisc <= OuroSheetMetrics.closeTarget)
    }

    /// In dark a sheet has a hairline rim in its words' colour, so it doesn't melt into the dimmed page; light needs none.
    @Test func aDarkSheetHasARim() {
        #expect(OuroSheetMetrics.rimOpacity(scheme: .dark) == 0.12)
        #expect(OuroSheetMetrics.rimOpacity(scheme: .light) == 0)
        #expect(OuroSheetMetrics.rimWidth == 0.5)
    }

    /// iOS 26 and later draw a sheet below its full height at 96% (measured: a 44-point button reads 42.2 in the
    /// gallery's UI tests). Inside `.ouroSheet`, controls are sized up so they are still 44 points as drawn.
    @Test func aSheetsControlsAre44PointsAsDrawn() {
        #expect(OuroSheetMetrics.closeTarget * OuroSheetMetrics.drawnScale >= 44)
        #expect(OuroSheetMetrics.touchTarget * OuroSheetMetrics.drawnScale >= 44)
        for size in OuroButtonSize.allCases {
            #expect(size.minimumHeight(on: .touch, target: OuroSheetMetrics.touchTarget) * OuroSheetMetrics.drawnScale >= 44)
        }
        #expect(OuroButtonSize.md.minimumHeight(on: .touch, target: 44) == 50)
        #expect(OuroButtonSize.lg.minimumHeight(on: .touch, target: OuroSheetMetrics.touchTarget) == 56)
        #expect(OuroButtonSize.sm.minimumHeight(on: .pointer, target: OuroSheetMetrics.touchTarget) == 28)
    }
}

// MARK: contrast.text

@Suite struct ContrastTests {
    /// Your own text on a theme surface reads at the components' target: muted text on a card, in every theme and mode.
    @Test func yourOwnTextReadsAtTheComponentsTarget() {
        for (name, style) in styles {
            let c = style.colors
            let shown = OuroColor.readable(c.mutedForeground, on: c.card, contrast: style.contrast)
            #expect(ratio(OuroColor.resolve(shown), OuroColor.resolve(c.card)) >= target(style), "\(name)")
        }
        // A colour that already reads is left alone.
        #expect(OuroColor.readable(.black, on: .white) == .black)
    }

    @Test(arguments: OuroButtonVariant.allCases)
    func everyButtonLabelReadsOnItsFillInEveryThemeAndMode(variant: OuroButtonVariant) {
        for (name, style) in styles {
            for tone in OuroTone.allCases {
                let p = OuroButtonPalette(tone: tone, variant: variant, style: style)
                #expect(ratio(p.label, p.surface) >= target(style), "\(name) \(tone) \(variant): \(ratio(p.label, p.surface))")
            }
        }
    }

    /// A disabled button looks disabled (the muted colours, not its tone) and its label still reads: Xcode's audit
    /// fails a half-transparent label, and people with low vision still need to read what they can't press yet.
    @Test(arguments: OuroButtonVariant.allCases)
    func aDisabledButtonsLabelStillReads(variant: OuroButtonVariant) {
        for (name, style) in styles {
            for tone in OuroTone.allCases {
                let p = OuroButtonPalette(tone: tone, variant: variant, style: style, isEnabled: false)
                #expect(ratio(p.label, p.surface) >= target(style), "\(name) \(tone) \(variant) disabled")
                // Tellable apart: the label or the fill moves visibly in colour (a tone turning grey, or a grey
                // moving in lightness), or an outline reads at 1.5:1 on the fill.
                let enabled = OuroButtonPalette(tone: tone, variant: variant, style: style)
                let label = distance(p.label, enabled.label)
                let fill = distance(p.fill ?? p.surface, enabled.fill ?? enabled.surface)
                let outline = p.border.map { ratio($0, p.surface) } ?? 1
                #expect(label >= 0.2 || fill >= 0.2 || outline >= 1.5, "\(name) \(tone) \(variant): looks enabled (label \(label), fill \(fill), outline \(outline))")
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

    /// A soft fill is a 14% wash of its tone in light and 26% in dark, where a fainter one over near-black reads as
    /// mud.
    /// Secondary's solid fill is a step stronger than its soft one, so the two variants never look the same; under
    /// increased contrast an outline is two points wide, in its full tone.
    @Test func aSecondarySolidIsStrongerThanItsSoft() {
        #expect(OuroButtonMetrics.secondarySolidStep(scheme: .light) == 0.1)
        #expect(OuroButtonMetrics.secondarySolidStep(scheme: .dark) == 0.12)
        // Secondary's outline is the page's foreground at 25%, so it reads with the tones' outlines.
        for (name, style) in styles where style.contrast != .increased {
            let c = style.colors
            let p = OuroButtonPalette(tone: .secondary, variant: .outline, style: style)
            let line = OuroInk.tint(OuroInk.r(c.foreground), over: OuroInk.r(c.background), OuroButtonMetrics.neutralOutlineTint)
            #expect(distance(p.border!, line) < 0.01, "\(name)")
        }
        #expect(OuroButtonMetrics.neutralOutlineTint == 0.25)
        // A plain button's words sit on the layout margin, its target reaching past them.
        #expect(OuroButtonSize.md.horizontalPadding(for: .plain) == 0)
        #expect(OuroButtonSize.md.horizontalPadding(for: .solid) == 20)
        for (name, style) in styles {
            let solid = OuroButtonPalette(tone: .secondary, variant: .solid, style: style).fill!
            let soft = OuroButtonPalette(tone: .secondary, variant: .soft, style: style).fill!
            let background = OuroInk.r(style.colors.background)
            #expect(ratio(solid, background) > ratio(soft, background) * 1.06, "\(name): \(ratio(solid, background)) vs \(ratio(soft, background))")
        }
        #expect(OuroButtonMetrics.outlineWidth(contrast: .standard) == 1)
        #expect(OuroButtonMetrics.outlineWidth(contrast: .increased) == 2)
    }

    @Test func aSoftFillIsStrongerInDark() {
        #expect(OuroButtonMetrics.softTint(scheme: .light) == 0.14)
        #expect(OuroButtonMetrics.softTint(scheme: .dark) == 0.26)
    }

    /// An outline is drawn in its tone at 50% over the page, not the theme's neutral border, so the outline row reads
    /// as five tones; secondary keeps the border. Under increased contrast it reads at 3:1.
    @Test func anOutlineIsDrawnInItsTone() {
        for (name, style) in styles {
            let c = style.colors
            let background = OuroInk.r(c.background)
            for tone in OuroTone.allCases where tone != .secondary {
                let p = OuroButtonPalette(tone: tone, variant: .outline, style: style)
                guard let border = p.border else { Issue.record("\(name) \(tone): no outline"); continue }
                if style.contrast == .increased {
                    #expect(ratio(border, background) >= OuroColor.increasedLineContrast, "\(name) \(tone)")
                } else {
                    let wash = OuroInk.tint(OuroInk.r(tone.fill(c).fill), over: background, 0.5)
                    #expect(distance(border, wash) < 0.01, "\(name) \(tone): \(distance(border, wash))")
                }
            }
        }
    }

    /// A banner's description is the plain secondary colour, not tinted toward the tone, and the neutral banner's
    /// icon is secondary too, not the heaviest mark on the page. In dark the wash is 15% of the tone over the raised
    /// card colour.
    /// A banner has an edge in its tone (25% in light, 30% in dark) so it reads as a surface rather than a stain; under
    /// increased contrast the edge is its full tone, raised to 3:1, two points wide. Corners are 20 points.
    @Test func aBannerIsEdgedInItsTone() {
        #expect(OuroBannerMetrics.cornerRadius == 16)
        #expect(OuroBannerMetrics.edgeTint(scheme: .light) == 0.25)
        #expect(OuroBannerMetrics.edgeTint(scheme: .dark) == 0.3)
        for (name, style) in styles {
            let c = style.colors
            let background = OuroInk.r(c.background)
            for tone in OuroTone.allCases where tone != .secondary {
                let p = OuroBannerPalette(tone: tone, style: style)
                let toneColour = OuroInk.r(tone.fill(c).fill)
                if style.contrast == .increased {
                    #expect(ratio(p.border, p.surface) >= OuroColor.increasedLineContrast, "\(name) \(tone)")
                } else {
                    let base = style.scheme == .dark ? OuroInk.r(c.card) : background
                    let edge = OuroInk.tint(toneColour, over: base, OuroBannerMetrics.edgeTint(scheme: style.scheme))
                    #expect(distance(p.border, edge) < 0.01, "\(name) \(tone): \(distance(p.border, edge))")
                }
            }
        }
    }

    @Test func aBannersWordsAreNotTinted() {
        for (name, style) in styles {
            let c = style.colors
            for tone in OuroTone.allCases {
                let p = OuroBannerPalette(tone: tone, style: style)
                let plain = OuroInk.readable(OuroInk.r(c.mutedForeground), on: p.surface, style)
                #expect(distance(p.description, plain) < 0.01, "\(name) \(tone) description")
                if tone == .secondary { #expect(distance(p.icon, plain) < 0.01, "\(name) secondary icon") }
                if tone != .secondary, style.scheme == .dark {
                    let wash = OuroInk.tint(OuroInk.r(tone.fill(c).fill), over: OuroInk.r(c.card), 0.12)
                    #expect(distance(p.surface, wash) < 0.01, "\(name) \(tone) surface")
                }
            }
        }
    }

    /// An empty state's symbol is quiet, the secondary colour, with or without an action, as the system's own are; the
    /// title carries the state and an action the colour.
    @Test func anEmptyStatesSymbolIsQuiet() {
        for (name, style) in styles {
            let c = style.colors
            let surface = OuroInk.r(c.background)
            let p = OuroEmptyStatePalette(style: style)
            #expect(distance(p.icon, OuroInk.readable(OuroInk.r(c.mutedForeground), on: surface, style)) < 0.01, "\(name)")
        }
        #expect(OuroEmptyStateMetrics.symbolWeight == .semibold)
    }

    /// On glass a toast's words take the system's vibrant styles, which follow the colour scheme, not the theme. They
    /// are used only where they read on the theme's surface under the glass: a custom theme with a dark popover in
    /// light mode gets its own colours, solid, instead.
    @Test func vibrantWordsAreUsedOnlyWhereTheyRead() {
        let white = Color.Resolved(red: 1, green: 1, blue: 1)
        let black = Color.Resolved(red: 0.05, green: 0.05, blue: 0.06)
        #expect(OuroToastPalette.vibrantReads(on: white, scheme: .light, contrast: .standard))
        #expect(!OuroToastPalette.vibrantReads(on: black, scheme: .light, contrast: .standard))
        #expect(OuroToastPalette.vibrantReads(on: black, scheme: .dark, contrast: .standard))
        #expect(!OuroToastPalette.vibrantReads(on: white, scheme: .dark, contrast: .standard))
        for (name, style) in styles where style.contrast == .standard {
            #expect(OuroToastPalette(tone: .success, style: style).vibrant, "\(name): the shipped themes keep the glass words")
        }
    }

    /// A toast's action is tinted words, not a button inside the capsule, reading on the toast's surface.
    @Test func aToastsActionReadsOnItsSurface() {
        for (name, style) in styles {
            for tone in OuroTone.allCases {
                let p = OuroToastPalette(tone: tone, style: style)
                // 7:1 in every mode: inside the glass, vibrancy lightens tinted words.
                #expect(ratio(p.action, p.surface) >= OuroColor.increasedTextContrast, "\(name) \(tone) action")
                #expect(ratio(p.divider, p.surface) > 1, "\(name) \(tone) divider")
            }
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
        #expect(OuroToastMetrics.appearance(reduceMotion: false) == .drop)
        #expect(OuroAppearance.drop.step(reduceMotion: false) == OuroMotion.step(.enter, reduceMotion: false))
        #expect(OuroToastMetrics.appearance(reduceMotion: true) == .fade)
        #expect(OuroToastMetrics.arrival(reduceMotion: true) == .crossfade(duration: OuroTokens.Duration.base))
        #expect(OuroToastMetrics.departure(reduceMotion: true) == .crossfade(duration: OuroTokens.Duration.base))
        #expect(OuroBannerMetrics.appearance(reduceMotion: false) == .unfold)
        #expect(OuroAppearance.unfold.step(reduceMotion: false) == OuroMotion.step(.layout, reduceMotion: false))
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

    /// A toast arrives on a spring with a little bounce and leaves on one with none, so it never wobbles away.
    @Test func aToastArrivesWithABounceAndLeavesWithout() {
        // A livelier landing than other arrivals, so the overshoot shows: 0.5 s, bounce 0.32. It leaves shrinking to 96%.
        #expect(OuroToastMetrics.arrival(reduceMotion: false) == .spring(visualDuration: 0.5, bounce: 0.32))
        #expect(OuroToastMetrics.departureScale == 0.96)
        #expect(OuroToastMetrics.departure(reduceMotion: false) == OuroMotion.step(.exit, reduceMotion: false))
    }

    /// A drag follows the finger up, the way out, and only a third of the way down, where there is nowhere to go.
    /// Let go far enough up, or flung up, it goes; otherwise it springs back.
    @Test func aToastFollowsADragUpAndRubberBandsDown() {
        #expect(OuroToastMetrics.dragOffset(-40) == -40)
        #expect(OuroToastMetrics.dragOffset(30) == 9)
        #expect(OuroToastMetrics.dragDismisses(translation: -31, predictedEnd: -31))
        #expect(OuroToastMetrics.dragDismisses(translation: -10, predictedEnd: -120))
        #expect(!OuroToastMetrics.dragDismisses(translation: -20, predictedEnd: -40))
        #expect(!OuroToastMetrics.dragDismisses(translation: 60, predictedEnd: 200))
    }

    /// Collapsed, older toasts tuck behind the newest, peeking 12 then 22 points, at 95% and 90%, words hidden. They stay
    /// opaque, shaded 4% then 8% toward the words' colour, so the page never shows through a peek; expanded, every toast
    /// shows its words, listed below the newer ones.
    /// A tucking toast's words fade in at most 0.1 s, so they are gone before its plate slides under the one arriving.
    @Test func aTuckingToastsWordsFadeWithinATenthOfASecond() {
        #expect(OuroToastMetrics.wordsFadeSeconds <= 0.1)
    }

    @Test func onlyTheFrontToastsFirstSizeTucksTheStackSoOnlyItIsAnimated() {
        #expect(OuroToastMetrics.resizesTuckedOnMeasure(depth: 0, count: 2, measured: false))
        #expect(!OuroToastMetrics.resizesTuckedOnMeasure(depth: 0, count: 2, measured: true))
        #expect(!OuroToastMetrics.resizesTuckedOnMeasure(depth: 0, count: 1, measured: false))
        #expect(!OuroToastMetrics.resizesTuckedOnMeasure(depth: 1, count: 3, measured: false))
    }

    @Test func aTuckingToastKeepsItsSizeUntilTheNewOneIsMeasured() {
        let own = CGSize(width: 220, height: 56), front = CGSize(width: 260, height: 56)
        #expect(OuroToastMetrics.tuckedSize(front: nil, own: own) == own)
        #expect(OuroToastMetrics.tuckedSize(front: front, own: own) == front)
        #expect(OuroToastMetrics.tuckedSize(front: front, own: nil) == front)
    }

    /// A tucked toast draws no border of its own, only the hairline, so the stack reads as one toast with depth, not a
    /// drawer of outlined cards; the front one has its border when solid.
    @Test func aTuckedToastHasNoBorder() {
        #expect(OuroToastMetrics.outline(solid: true, tucked: true, edge: 0.08) == .init(edge: 0.08, border: 0))
        #expect(OuroToastMetrics.outline(solid: true, tucked: false, edge: 0.08) == .init(edge: 0, border: 1))
        #expect(OuroToastMetrics.outline(solid: false, tucked: false, edge: 0.08) == .init(edge: 0.08, border: 0))
    }

    /// A banner's and a toast's icons grow with their words, up to the same size.
    @Test func bannerAndToastIconsGrowAlike() {
        #expect(OuroBannerMetrics.largestIconSize == .accessibility3)
        #expect(OuroToastMetrics.largestIconSize == .accessibility3)
    }

    @Test func olderToastsTuckBehindTheNewest() {
        let front = OuroToastMetrics.placement(depth: 0, expanded: false, above: 0)
        #expect(front.offset == 0 && front.scale == 1 && front.shade == 0 && front.showsWords)
        let second = OuroToastMetrics.placement(depth: 1, expanded: false, above: 56)
        #expect(second.offset == 12 && abs(second.scale - 0.95) < 1e-9 && abs(second.shade - 0.04) < 1e-9 && !second.showsWords)
        let third = OuroToastMetrics.placement(depth: 2, expanded: false, above: 112)
        #expect(third.offset == 22 && abs(third.scale - 0.9) < 1e-9 && abs(third.shade - 0.08) < 1e-9)
        let listed = OuroToastMetrics.placement(depth: 2, expanded: true, above: 100)
        #expect(listed.offset == 116 && listed.scale == 1 && listed.shade == 0 && listed.showsWords)
    }

    /// A toast has a hairline edge in every mode, so a light toast on a light page doesn't lean on its shadow alone.
    @Test func aToastHasAHairlineEdge() {
        #expect(OuroToastMetrics.edgeWidth == 0.5)
        #expect(OuroToastMetrics.edgeOpacity(scheme: .light) == 0.08)
        #expect(OuroToastMetrics.edgeOpacity(scheme: .dark) == 0.12)
    }

    /// A toast can carry its own symbol, so a secondary one ("Recipe deleted") has a mark like the rest; without one,
    /// its tone's.
    @Test func aToastCanCarryItsOwnSymbol() {
        #expect(OuroToast("Recipe deleted", systemImage: "trash").symbol == "trash")
        #expect(OuroToast("Saved", tone: .success).symbol == "checkmark.circle.fill")
        #expect(OuroToast("Plain").symbol == nil)
    }

    /// One light shadow under the stack, as Apple's notices cast: black at 8%, a 12-point blur dropped 4 points. Tucked
    /// toasts cast none, so three shadows never add up to a grey band.
    @Test func aToastCastsOneLightShadow() {
        #expect(OuroToastMetrics.shadow == .init(opacity: 0.12, radius: 20, y: 6))
        #expect(OuroToastMetrics.shadowReach == 26)
        #expect(OuroToastMetrics.castsShadow(tucked: false))
        #expect(!OuroToastMetrics.castsShadow(tucked: true))
    }

    /// A banner's words fade out by the time it is half folded, so the page closing up never slides over words that
    /// are still showing; unfolding, they fade in over the second half.
    @Test func aFoldingBannerIsGoneByHalfway() {
        #expect(OuroBannerMetrics.foldOpacity(progress: 0) == 0)
        #expect(OuroBannerMetrics.foldOpacity(progress: 0.5) == 0)
        #expect(OuroBannerMetrics.foldOpacity(progress: 0.6) == 0)
        #expect(abs(OuroBannerMetrics.foldOpacity(progress: 0.8) - 0.5) < 1e-9)
        #expect(OuroBannerMetrics.foldOpacity(progress: 1) == 1)
    }

    @Test func aStackIsNotScaledUnderReduceMotion() {
        let tucked = OuroToastMetrics.placement(depth: 2, expanded: false, above: 100, reduceMotion: true)
        #expect(tucked.scale == 1 && !tucked.showsWords)
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

    /// A sheet counts as drawn scaled only when its close button is drawn smaller than its layout size: 44.2 points
    /// at 96%, 46 unscaled. That holds on any platform and OS, where a sheet's height says nothing.
    @Test func aSheetIsScaledOnlyWhenItsCloseButtonIsDrawnSmall() {
        #expect(OuroSheetMetrics.isDrawnScaled(closeButtonHeight: 46 * 0.96))
        #expect(!OuroSheetMetrics.isDrawnScaled(closeButtonHeight: 46))
        #expect(!OuroSheetMetrics.isDrawnScaled(closeButtonHeight: 0))
        #expect(OuroSheetMetrics.accessibilityIdentifier == "ouro.sheet")
        #expect(OuroSheetMetrics.closeIdentifier == "ouro.sheet.close")
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

/// Where a whole-sheet scroll goes as the keyboard comes up at the accessibility sizes: as far toward its end (the
/// actions) as keeps the focused field wholly in view, its top first when it can't all fit.
@Suite struct SheetKeyboardScrollTests {
    // 1,000 points of content in a 600-point view, 300 of it under the keyboard: the end is offset 700.
    let room = (content: 1000.0, viewport: 600.0, top: 0.0, bottom: 300.0)

    func offset(_ field: CGRect?) -> CGFloat {
        OuroSheetMetrics.keyboardOffset(field: field, contentHeight: room.content, viewport: room.viewport,
                                        topInset: room.top, bottomInset: room.bottom)
    }

    @Test func withNoFieldItGoesToTheEnd() {
        #expect(offset(nil) == 700)
    }

    @Test func aFieldJustAboveTheActionsAlsoGoesToTheEnd() {
        #expect(offset(CGRect(x: 0, y: 800, width: 300, height: 60)) == 700)
    }

    @Test func aFieldNearTheTopStaysInViewRatherThanTheEnd() {
        // The field's top, less the margin, is the top of the view: the actions wait below.
        #expect(offset(CGRect(x: 0, y: 200, width: 300, height: 60)) == 200 - OuroSheetMetrics.keyboardFieldMargin)
    }

    @Test func aFieldAtTheVeryTopNeverScrollsPastTheStart() {
        #expect(offset(CGRect(x: 0, y: 4, width: 300, height: 60)) == 0)
    }

    @Test func aFieldTallerThanTheRoomKeepsItsTop() {
        #expect(offset(CGRect(x: 0, y: 300, width: 300, height: 500)) == 300 - OuroSheetMetrics.keyboardFieldMargin)
    }

    @Test func contentThatFitsDoesNotScroll() {
        #expect(OuroSheetMetrics.keyboardOffset(field: CGRect(x: 0, y: 100, width: 300, height: 60), contentHeight: 250,
                                                viewport: 600, topInset: 0, bottomInset: 300) == 0)
    }

    @Test func theKeyboardEdgeNeverCutsThroughTheActions() {
        // The field near the top would leave the visible room ending at 484, through actions at 450 to 550: the sheet
        // scrolls back until the actions start at the keyboard's edge, the field still in view.
        let y = OuroSheetMetrics.keyboardOffset(field: CGRect(x: 0, y: 200, width: 300, height: 60), actions: 450...550,
                                                contentHeight: 1000, viewport: 600, topInset: 0, bottomInset: 300)
        #expect(y == 150)
    }

    @Test func actionsWhollyUnderTheKeyboardStayThere() {
        let y = OuroSheetMetrics.keyboardOffset(field: CGRect(x: 0, y: 200, width: 300, height: 60), actions: 600...700,
                                                contentHeight: 1000, viewport: 600, topInset: 0, bottomInset: 300)
        #expect(y == 200 - OuroSheetMetrics.keyboardFieldMargin)
    }

    @Test func actionsWhollyInViewStayThere() {
        let y = OuroSheetMetrics.keyboardOffset(field: CGRect(x: 0, y: 800, width: 300, height: 60), actions: 880...1000,
                                                contentHeight: 1000, viewport: 600, topInset: 0, bottomInset: 300)
        #expect(y == 700)
    }

    // A header of two title lines and three description lines at the largest size: its words run 20 to 392, and the
    // top edge may fall only between lines.
    let header: ClosedRange<CGFloat> = 20...392
    let stops: [CGFloat] = [20, 105, 190, 194, 260, 326, 392]

    @Test func theTopEdgeNeverCutsThroughTheTitle() {
        // One field: the end (220) would slice the description; the nearest line gap that keeps the field and the
        // actions whole is 260, past the end, which the sheet pads to reach.
        let y = OuroSheetMetrics.keyboardOffset(field: CGRect(x: 0, y: 420, width: 300, height: 100), actions: 530...690,
                                                header: header, stops: stops, contentHeight: 700, viewport: 780,
                                                topInset: 0, bottomInset: 300)
        #expect(y == 260)
    }

    @Test func stoppingShortOfTheActionsNeverCutsTheDescription() {
        // Two fields: the field's place (404) would cut the actions, and stopping short of them (380) the description;
        // the line gap at 326 does neither.
        let y = OuroSheetMetrics.keyboardOffset(field: CGRect(x: 0, y: 420, width: 300, height: 100), actions: 860...1020,
                                                header: header, stops: stops, contentHeight: 1030, viewport: 780,
                                                topInset: 0, bottomInset: 300)
        #expect(y == 326)
    }

    @Test func anEdgeBetweenRowsStaysPut() {
        let y = OuroSheetMetrics.keyboardOffset(field: CGRect(x: 0, y: 420, width: 300, height: 100), actions: 920...1080,
                                                header: header, stops: stops, contentHeight: 1090, viewport: 780,
                                                topInset: 0, bottomInset: 300)
        #expect(y == 404)
    }

    @Test func aTopInsetIsHonoured() {
        // Offsets run from -top: the field's top sits just under the inset.
        #expect(OuroSheetMetrics.keyboardOffset(field: CGRect(x: 0, y: 200, width: 300, height: 60), contentHeight: 1000,
                                                viewport: 600, topInset: 20, bottomInset: 300)
                == 200 - OuroSheetMetrics.keyboardFieldMargin - 20)
    }
}
