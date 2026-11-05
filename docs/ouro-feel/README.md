# Ouro Feel

Ouro Feel measures how an Apple app feels, deterministically, from a UI test. It turns the checks taste reviewers kept
rewriting by hand into one library every app runs in CI, so agents spend their own judgement only on taste
([taste-rubric.md](taste-rubric.md)).

- **`OuroFeel`** (link it into your UI test bundle) drives XCUITest and reads accessibility snapshots.
- **`OuroFeelCore`** is the pure analysis behind it: no XCTest, so every rule has a unit test (`Tests/OuroFeelTests`).
- **`scripts/ouro-feel-cold.sh`** runs one test N times on fresh simulators and reports the pass rate.

Credit: the checks come from Gatefold's build 17 to 19 reviewer drivers (tap rate, row feel, Settings control,
portrait panel, rotation), Spoonjoy's W10 and W10b jank tools (frame sheets, jump and double-draw scans) and the HX
gallery's motion gate (hitch ratio, from `FrameProbe`).

## Add it

```swift
// Package.swift or Xcode: the UI test target depends on the OuroFeel product.
.package(url: "https://github.com/ourostack/ouro-ui-apple", from: "0.4.0")
```

```swift
import OuroFeel
import XCTest

@MainActor
final class FeelTests: XCTestCase {
    func testTheWayBack() {
        let app = XCUIApplication()
        app.launch()
        let feel = OuroFeel(app)
        feel.expect(feel.wayBack(from: [.launch, .tab("Kitchen")]))
    }
}
```

`feel.expect(result)` attaches the report to the test, prints it with an `[ouro-feel]` prefix, writes it as text and
JSON to `OURO_FEEL_REPORT_DIR` (pass `TEST_RUNNER_OURO_FEEL_REPORT_DIR=<dir>` to `xcodebuild`), and fails the test if
the check failed. `feel.record(result)` does the same without failing, for a test that expects a known bug to be
caught.

## The genres

Each check covers one genre of jank (`FeelGenre`). The way back is the app-wide one: give it your entry points and it
visits every screen it can reach by tapping cells, links and buttons, checking each screen's layout on the way. Name the
overlays to check; the motion and place checks watch the elements and steps you give them.

| Genre | What good feels like | Check |
|---|---|---|
| the way back | Every screen you reach has a visible way back and a gesture back, and both return you where you were. | `feel.wayBack(from:follow:depth:)` |
| overlay dismissal | Every sidebar, popover and menu goes away with a tap outside it, and once you pick something in it. | `feel.overlays(_:)` |
| inside the window | Every control sits wholly inside the window, in every orientation and after turning the device and back. | `feel.insideWindow(poses:)`; also on every screen `wayBack` reaches |
| tap landing | One tap anywhere on a control works, every time, with no second try. | `feel.tapLanding(on:trials:spots:title:rowToggles:baseline:rapidBaseline:)`, `feel.osBaseline(rapid:)` |
| double-draw | Each piece of content is on screen once; nothing shows a ghost copy mid-transition. | `film.doubleDraws(of:)` |
| jump after landing | Once something lands it stays put; nothing nudges it afterwards. | `film.jumps(of:rest:limit:)` |
| late or lingering chrome | Bars and controls hand over in one beat: never two states at once, never a blank between them. | `film.chrome(from:to:grace:)` |
| snap with no transition | Things that move travel there; nothing teleports across the screen. | `film.snaps(of:distance:appearing:)` |
| settle time | The screen comes to rest promptly after you act. | `film.settles(_:within:)` |
| place stability | Reopen, relaunch or turn the device and you are exactly where you were. | `feel.place(across:read:)` |
| hitches (a measure) | Motion runs at the display's pace with no visible stall. | `FeelHitches.analyze(timestamps:refresh:)`, `feel.measureHitches(in:)` |

### The way back

Proves: every screen reachable from your entry points, up to `depth` taps deep, has a visible back control (a
navigation bar's leading button, or a Back, Close, Done, Cancel or Dismiss button inside the window) that returns, and
a gesture (an edge swipe, else a swipe down) that returns. It also checks each reached screen's controls lie inside
the window (`alsoInsideWindow: false` turns that off).

Flags: `from:` entry points (`.launch`, `.tab("Kitchen")`, or `FeelEntry("name") { app in … }`); `follow:` what it
may tap (cells and links by default; `FeelFollow(types: [.cell, .link, .button])` reaches sheets and covers too;
`FeelFollow(types: [], prefixes: ["recipe."])` for only your own identifiers). It never taps a back control, a menu
button (a SwiftUI `Menu` shows up as a plain button, so the walk taps it and checks the menu as an overlay), anything inside a tab bar, segmented control, picker or menu (they switch what a screen shows), or one whose
identifier or label says delete, remove, sign out, clear, pay, checkout, send, share or the like
(`FeelSafety.dangerous`, matched across camelCase, acronyms and punctuation). A tap that leaves the navigation bars as they were and most of the screen's controls still there did
not reach a new screen, and neither did one that hid the screen but brought no navigation bar or way back of its own
and covers under 60% of the window (a system menu hides what is behind it). What such a tap added is an overlay when
it hid the screen or floats over controls that stayed where they were; otherwise it changed the screen in place
(edit mode, a row expanding, "Show more"), which the report notes. If new elements appeared (a menu, a popover), the walk checks that overlay as the overlay
genre does: a tap outside it, on nothing the screen behind would act on, must close it, and so must picking its
topmost safe item; one that stays open fails the way back. If a pick leaves the screen, the walk relaunches back rather
than carrying on from there, and a control that is gone by the time the walk comes to it is reported as not checked.
Two limits: a pushed screen with its bar hidden, or a cover with no Close button, that covers under 60% of the window
is judged as an overlay, so it fails as "a tap outside did not dismiss it" rather than "no visible way back"; and a
half-height sheet with no navigation bar is expected to close on a pick, as a menu does; and a label or badge
that appears over a control for good (a like count) reads as an overlay that did not close. The keyboard is never
part of the screen or an overlay. After a pick, the walk re-reads the screen's controls, so a row the pick renamed is
followed under its new name; a screen whose controls keep renaming stops the walk there after three times as many
tries as it first found, reported as not checked. The walk relaunches the app only to recover (an
overlay that stayed open, a screen it could not leave), lists every relaunch in the report, and says how many in the
summary line, so a PASS is never read as recovery-free. When buttons are followed, Save or Add can still be tapped, so launch into a fixture state
that is safe to change and repeat. `depth:` (default 2), `limit:` (default 40 screens); each screen already seen costs a
relaunch, so keep long lists out of the walk with `prefixes`. Its edge swipe starts at the navigation bar's height,
above any list row, so a missing pop gesture never fires a row's swipe action.

Before each gesture the walk waits for the screen to land (navigation bars and buttons holding still), since a push
still sliding in ignores a back swipe. Run the walk on an iPhone simulator: on the iOS 27.2 iPad simulator it finds the
visible way back, but its edge swipe and swipe down did not return even from a plain push, so on iPad it reports
missing gestures that a person would not miss. Making the gestures work on iPad is planned for v0.2.

```swift
feel.expect(feel.wayBack(from: [.launch], follow: FeelFollow(prefixes: ["recipe.", "chef."]), depth: 2))
```

### Overlay dismissal

Proves: each overlay you name appears, goes away on a tap outside it, and (with `pick:`) goes away once you pick an
item in it, as a compact sidebar should.

```swift
feel.expect(feel.overlays([
    .button("sidebar.toggle", overlay: "sidebar", pick: "sidebar.saved"),
    .button("Sort", overlay: "sort.menu"),
]))
```

### Inside the window

Proves: every enabled control's frame lies inside the window frame in portrait, landscape, and portrait again after
the round trip (`FeelPose.roundTrip`). It compares frames and never asks `isHittable`, because the simulator accepts
XCUITest taps past the window's edge where no finger can reach. A control scrolled out of view passes when its scroll
view is inside the window and the control is off only along the way it scrolls. Accessibility does not say which way
that is, so a scroll view counts as a sideways carousel only when it is wide, its content runs off its sides, and it is
under 60% of the window's height; any other is a list, which never excuses a control off the side. A full-screen
sideways pager therefore fails with its next page off the side: check it with `poses:` on a screen without one, or
read the finding. When the app stays portrait as the device turns, the report adds a note, marked as inference, and the check still passes.

```swift
feel.expect(feel.insideWindow())                     // portrait, landscape, portrait again
feel.expect(feel.insideWindow(poses: [.current]))    // just as it is
```

### Tap landing

Proves: single taps, never retried, land at the centre and the four edges (4 pt in). A zero-length press
(`.zeroPress`) is opt-in: a system Toggle ignored it 3 times in 3 on the iOS 27.2 simulator, so it is only fair for a
control that acts on touch-down. With a
`title:` it also taps the row's title and the gap beside it: `rowToggles: true` when the row acts as one button,
`false` (default) when it should not. A tap lands when `read` (default: the control's value) changes within `within` seconds (default 3, since a busy
simulator is slow to report a change).
Paced taps wait 0.6 s after each one for the control to settle.
`baseline:` takes `feel.osBaseline()`, the same loop on a Settings switch on this simulator; when that misses too, the
report marks "the simulator may be dropping taps" as inference.

People also tap while a control is still animating. For a control with two states (a switch, a checkbox, passed
as the element itself), `rapid:` adds that many double taps at its centre (off by default, since a counter, a stepper
or a row that opens a screen never ends where it started), each from a settled control. A pair that ends where it
started had both taps land, or neither; one that ends changed lost a tap. It is read from where the control ends, so
the report marks it as inference, and it is scored only when the paced single taps at the centre all landed (otherwise could not check). XCUITest's
single taps wait for the app to go idle, about 0.6 s apart, so only its double tap sends taps faster than an animation.
Because "neither landed" also ends where it started, one triple tap follows the pairs (an element tap, since a coordinate has no triple; the same touch path): if every pair
ended where it started, the triple must end changed to show quick taps reach the control, or the result is could not
check. That catches a control that swallows every burst, not one that eats exactly the second tap of each.

The bar is absolute: every pair must end where it started. Our bar is higher than UIKit's: on the iOS 27.2 simulator
the Settings switch (a UIKit switch) kept only the first tap of a double tap, 0 pairs in 5, while a SwiftUI `Toggle`
kept both in 5 of 5. So `rapidBaseline:` (`feel.osBaseline(rapid: true)`, the same double taps on a Settings switch's
knob, since XCUITest gives that switch the whole row's frame, where a tap does nothing) is opt-in context only: the
report gives both rates (`rapid rate`, `rapid baseline`) and says "the OS control also drops these", but a baseline
never turns a fail into a pass.

```swift
let baseline = feel.osBaseline()
let rapidBaseline = feel.osBaseline(rapid: true)
feel.expect(feel.tapLanding(on: app.switches["appearance.pageNumbers"], trials: 5,
                            title: app.staticTexts["Page Numbers"], rowToggles: true,
                            baseline: baseline, rapid: 5, rapidBaseline: rapidBaseline))
```

### Motion: double-draw, jump after landing, chrome, snap, settle

A film samples the elements you name (identifiers or labels) from accessibility snapshots for a number of seconds;
every motion check reads the same film.

```swift
let film = feel.film(["cook.cover", "Pancakes", "bar.full", "bar.compact"], for: 4)
feel.expect(film.snaps(of: "cook.cover"))
feel.expect(film.jumps(of: "cook.cover"))                 // > 2 pt after 0.3 s at rest
feel.expect(film.doubleDraws(of: ["Pancakes"]))
feel.expect(film.chrome(from: "bar.full", to: "bar.compact"))
feel.expect(film.settles("cook.cover", within: 1.0))
```

**What a film can and cannot see.** XCUITest waits for the app to go idle after every tap, so a film started by a tap
(`film(_:for:every:during:)`) sees what happens after the transition (late jumps, lingering chrome, ghost copies that stay),
not the frames inside it. To film a transition itself, have the app start it a moment after the tap: a test-only
launch argument that delays it, as the fixture's Play button does (`-autoplay 2`, two seconds after the tap). Timing it
from launch is fragile: under load, launching took longer than the delay and the film began after the motion. A check
that sees no motion says "could not check"; it never passes.

What the samples show mid-transition (seen on the iOS 27.2 simulator): SwiftUI stretches an animating element's
accessibility frame from where it is drawn to where it is going, so a sample at another size than the element's resting
size is an in-between position. A snap is a big move between two samples at the resting size with the element still on
both sides. Sometimes a snapshot waits instead, and the move shows up inside one long gap in otherwise quick samples
(at least three times the usual gap). A transition and a snap with heavy layout both cause that, so the snap check
fails saying the move was not seen. When samples are usually more than 0.15 s apart (from watching too many elements,
or a busy machine) the snap and settle checks fail and say so. No motion check passes on an element it never saw.

Each snapshot holds the app's main thread while it answers, so a film samples every 0.05 s by default (`every:`);
in one run with back-to-back sampling a 0.8 s ease measured 1.84 s (we infer the sampling slowed it). Settle times are
timed on the test runner's clock and can run long under load, so leave margin in the limit. Settle fails when the
element was never seen moving (a film started by a tap begins after the motion is over) or was still moving when the
film ended. `jumps` counts moves after the first one, so start the film before the transition. Seeing every
frame of a transition needs host video or an in-app probe (planned for v0.2).

### Place stability

Proves: the place (by default every static text on screen) reads the same after each step: `.background`, `.rotate`,
`.relaunch` (the default list), or `FeelPlaceStep("reopen") { feel in … }`. It stores and reports only the first 16
hex digits of a SHA-256 of what it read, never the content.

```swift
feel.expect(feel.place(read: { app.otherElements["reader.page"].value as? String ?? "" }))
```

`.relaunch` reuses `app.launchArguments`, so drop any reset arguments before calling it.

### Hitches

`FeelHitches.analyze(timestamps:refresh:)` turns display-link timestamps (from a probe in your app, such as the HX
gallery's `FrameProbe`) into a hitch ratio: under 5 ms/s is good, over 10 is critical (WWDC20, "Eliminate animation
hitches with XCTest"). `feel.measureHitches(in: self) { … }` wraps `XCTHitchMetric` (iOS 26 and later); its figures go
to the result bundle. On the simulator these numbers are a proxy that depends on the Mac; gate on a device.

## Cold starts

```sh
scripts/ouro-feel-cold.sh --project App.xcodeproj --scheme App --test AppUITests/FeelTests/testTheWayBack --runs 5
# AppUITests/FeelTests/testTheWayBack on iPhone 17 Pro (com.apple.CoreSimulator.SimRuntime.iOS-27-2), simulator: cold 5 of 5 passed
```

It builds once, then runs the test on a fresh simulator each time and deletes each one. `--warm` uses one simulator:
run 1 is cold and the rest are reported apart as warm. `--udid` erases and reuses a simulator you own. Every report
from those runs says `cold start (fresh simulator)` or `warm start`; a run the script did not start says the start is
not labelled and should be treated as warm. Never pass `-retry-tests-on-failure`: a retry hides the failure Feel
exists to find.

## Reading a report

```
FAIL the way back: 3 of 4 reachable screens have a way back and a gesture back
  - launch › nav.chef: no gesture back (neither an edge swipe nor a swipe down returned)
  measured: good=3, screens=4
  on simulator (iPhone 17 Pro, iOS 27.2), cold start (fresh simulator); timed by the test runner's wall clock, sampling accessibility snapshots
```

Every report names where it ran (simulator or device), how it started, and which clock timed it; a finding marked
`(inference)` goes beyond what was measured. A finding marked `(not checked)` is something the check could not judge
(the element was never on screen, samples were too far apart, the app was busy through a move): the check fails, its
summary starts "could not check:", and it is never counted as a bug (`result.detections` holds only the bugs). Fix the
test or rerun; do not report it as jank found. Say the same when you quote it.

## Proof

`Examples/OuroFeelFixture` has one page per genre with a known bug behind `-bug 1`. Its UI tests
(`FeelCatchesTests`) prove each check fails on the bug and passes without it; CI runs them on every pull request.
