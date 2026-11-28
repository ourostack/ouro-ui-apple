# 2026-11-27: Ouro Feel adds checks from Gatefold's jank hunt, and a posture principle

Status: accepted. Follows [2026-11-27: Ouro Feel holds principles, each with an open set of checks](2026-11-27-ouro-feel-principles.md).

## Context

On 2026-11-27 a lane hunted the jank left in Gatefold before its App Store release, on CI simulators (iPhone, iPad and
the iPhone Duo), and filed ourostack/gatefold#646 to #654: a Duo held like a book laid out as tabletop, with one column
across the fold (#646); opening it flat kept that layout for 10 s and more (#647); turns went through clipped,
stretched, tiny and doubled frames (#648, #649); a turn after a scroll lost the place (#650); jumps held the old page
4 to 8 s and on some screens landed only at the next tap (#651); a search hit landed under a pill (#652); a jump drew a
page that was neither the old one nor the target, for about 0.2 s each (#653); and a notice covered the first line of
every page (#654). The hunt proposed a check for each, and one more from its own notes (not public, and no issue was
filed): a dump of the Duo's reader showed its close button with a 14 by 14 point accessibility frame, which the notes
call unverified as a real tap-size problem. No Feel check caught any of them.

## Decision

1. **A new principle: posture changes re-lay out in place.** When the device turns, folds or unfolds, the screen lays
   out as if it had launched that way: nothing lingers from the old shape, and nothing runs across the fold. The fold
   and fresh-launch reports (#646, #647, #649) break that promise and no other principle says it, so per the
   principles record it is a principle of its own (`FeelPrinciple.posture`), not a stretch of place or canvas. A turn
   that loses the place (#650) is different: place's promise already says your place "stays put through relaunches,
   turns, stray touches and late replies", so that check is under place.
2. **The checks, each named for its promise:**

   | Check | Principle | Reports | Call |
   |---|---|---|---|
   | content clears the fold | posture | #646 | `feel.clearsTheFold` |
   | a turn lays out like a fresh launch | posture | #647, #649 | `feel.laysOutFresh` |
   | your place survives a turn | place | #650 | `feel.placeSurvivesTurns` |
   | a jump lands on its own, on time | intent | #651 | `feel.landsOnItsOwn` |
   | every target is big enough to hit | intent | the hunt's close button | `feel.targetsBigEnough` |
   | what you asked for lands in clear view | canvas | #652 | `feel.landsInClearView` |
   | a notice gets out of the way | canvas | #654 | `feel.noticeGivesWay` |
   | the screen shows only the before, the after or a veil | motion | #648, #649 (#653 not yet) | `feel.beforeAfterOrVeil` |

3. **Two proposals are one promise.** The hunt's rotation film (fail on any frame that is neither the before nor the
   after layout) and its "no foreign page on landing" (every frame of a jump is the old view, a veil or the target)
   are the same rule over different actions, so they are one check over a screen film shot with `cover: true`. It
   judges the states the screen rests on, not every frame: a turn's own animation and a cross-fade are frames on their
   way, and judging those would fail every turn. A wrong state shorter than a rest is left to a film at the display's
   pace, and that includes #653's, which lasted about 0.2 s each: this check does not catch #653 yet. The film's end is
   taken for the after only when a picture shot a second or two later matches it, so a wrong picture that outlasts the
   film is not passed as the after. A veil is a blank, the old view dimmed or washed evenly (#651's greyed page while a
   jump loads), or a picture the app passes in `veils:` (a skeleton, a material). A dimmed picture counts as the old
   view only once the dim is undone and it matches the old view, so a dimmed different page is not a veil. The later
   picture is blanked where the film was, so a clock in the status band is not read as a change.
4. **Motion's promise now says what it always meant.** Nothing moves unbidden: the screen only ever shows where it was
   or where it is going. Its name and id stay, so nothing that reads the catalog breaks.
5. **The fold is the app's to declare.** No CI simulator folds, so the fold check reads an element the app puts over
   its hinge (`ouro.fold`, at OuroHX's `OuroFoldRegion.frame`), or a frame the test passes. Its proof is its unit tests
   and the fixture's simulated fold; it has not run on a Duo, and nothing here says it has.
6. **A target's minimum is its platform's.** The HIG's accessibility table gives a default control size of 44 by 44
   points on iOS, iPadOS and watchOS, 28 on macOS, 60 on visionOS and 66 on tvOS, so `FeelTargets.minimum` is the
   platform's, not 44 everywhere.
7. **A turn has to happen to be judged.** A turn that leaves the window's shape as it was (a portrait-only app, or a
   platform where `FeelPose.turns` is the current pose) could not be checked, and nor could a turn after a scroll that
   moved nothing. The turn-place check reads twice, counting text partly shown: from the window's or the scroll view's
   top edge, for a page that keeps its place there (SwiftUI's default runs under the status bar, which shows in
   portrait only), and from below the status and navigation bars, for one that keeps it at the safe area's top
   (UIKit). A turn passes if any pairing of the readings is within a line. A place lost inside one long paragraph is
   not seen by either reading, so such a page passes `read:`.
8. **Nothing is counted.** The guide, the README, `AGENTS.md` and the principles record no longer say how many
   principles or checks there are; the catalog is the list.

Nothing the hunt proposed was left out, though one check does not yet catch #653 (above). Two parts were narrowed to what generalises: the fold check's "two-page
spread" is `spread: true`, asked for by a reader in book posture rather than required of every app (a list beside its
detail is a fine use of two sides), and the hunt's "panel never takes more than its own height" is not judged, since a
panel's own height is the app's to say; a panel that lingers or covers the page is caught by the fresh-launch and
cover checks. The jump budget defaults to 2 s for loaded CI simulators, since the hunt's timings came from hosted
simulators (#651 says they need measuring on a device).

## Prior art

Checked 2026-11-27.

| Prior art | Verdict | What we take |
|---|---|---|
| [Apple HIG, Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility#Mobility), "Offer sufficiently sized controls": default control sizes of 44x44 pt (iOS, iPadOS, watchOS), 28x28 pt (macOS), 60x60 pt (visionOS), 66x66 pt (tvOS) | adopt | Each platform's default as its line, by the frame accessibility reports |
| The HX gallery's `testEveryControlIs44Points` (`Examples/OuroHXGallery/UITests/ComponentClaimTests.swift`) | adopt | Buttons only, 0.01 pt of slack for rounding, the sheet grabber left out |
| [WCAG 2.2 SC 2.5.5 Target Size (Enhanced)](https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html) and [2.5.8 (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html) | borrow | Inline links in text are an exception, so `ignoring:` exists |
| [Android, "Make your app fold aware"](https://developer.android.com/guide/topics/large-screens/make-apps-fold-aware) (Jetpack WindowManager's `FoldingFeature`) | borrow | Avoid the fold's area and use it as a natural separator; a vertical fold is book posture |
| [Android, "Handle configuration changes"](https://developer.android.com/guide/topics/resources/runtime-changes) | borrow | A configuration change recreates the screen, so after a turn it should be what a fresh start in that configuration is |
| [WCAG 2.2 SC 2.4.11 Focus Not Obscured (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html) | borrow | What you moved to is not hidden by sticky content (banners, bars), the rule behind clear view and notices |
| [Nielsen Norman Group, "Response Times: The 3 Important Limits"](https://www.nngroup.com/articles/response-times-3-important-limits/) | borrow | About 1 s keeps the flow of thought; a jump's budget sits near it, raised for CI simulators |
| [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | borrow | Compare a picture with references; here the references are the film's own before and after |
| Feel's own `FeelCover`, `FeelScreenFilm.states`, `finishesIntent`'s wait and `FeelPlace.fingerprint` | adopt | Cover geometry, rests in a screen film, a single-tap wait, and fingerprints so no words reach a report |

## Consequences

- Gatefold adopts the checks in its Feel walk from the release that carries them, and each of #646 to #654 but #653 gets
  the check that would have caught it before its fix.
- An app that wants the fold check puts an accessibility element over its hinge. OuroHX could give a modifier that does
  it from `OuroFoldRegion`; that is left for when an app needs it.
- `FeelScreenFilm.contactSheet()` now lays out samples of different sizes, so a failing turn's film still saves its
  sheet.
- Still to add: the fold check on a real Duo through Device Hub, a jump's veil held past its budget (the hunt's "old page
  greyed"), and a film at the display's pace through a turn or a jump for wrong frames too brief to rest, which is what
  #653 needs.
- The new fixture tests are placed in the Feel shards by their times on CI run 46063430325 (`scripts/ui-shards.py`).
