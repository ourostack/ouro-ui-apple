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
(`FeelSafety.dangerous`, matched across camelCase, acronyms and punctuation). A tap reached a new screen when it replaced a navigation bar (known by its title and its back button's label, so an
untitled bar counts; Done, Cancel and Close do not name a bar), brought a bar with a back button, or took away most
of the screen's own texts and controls (the tab, navigation and toolbar chrome every screen shares is left out, and
content scrolled out of view still counts as there), so a push stays a push when its page shares a control with the
last one or scrolls under a tab bar. A tap that keeps the bars, most of the screen's controls and most of its content
did not reach a new screen, and neither did one that hid the screen but brought no navigation bar or way back of its own
and covers under 60% of the window (a system menu hides what is behind it). What such a tap added is an overlay when
it hid the screen or floats over controls that stayed where they were (never when it replaced the bar or the content); otherwise it changed the screen in place
(edit mode, a row expanding, "Show more"), which the report notes. A tap that swaps most of a screen's texts in place (paging, a filter row that rebuilds the
list) reads as a new screen and is asked for a way back; follow such controls out of the walk with `prefixes`. If new elements appeared (a menu, a popover), the walk checks that overlay as the overlay
genre does: a tap outside it, on nothing the screen behind would act on, must close it, and so must picking its
topmost safe item; one that stays open fails the way back. An item that opens a submenu is picked through it: only
when its header takes the picked item's place (or the item goes) is the submenu's own topmost item picked, and only
an item over the menu, never something new elsewhere (a toast's Undo), so a menu that stays open after a pick still
fails. A popover that holds only a stepper or slider (which it stays open to adjust) is asked only for the tap
outside; one that also has a button (Apply, or failing an item its Done or Close) must close on it. An overlay with
nothing safe to pick (each item reads as destructive) is asked only for the tap outside too. The report notes both. A
tap outside that goes through the overlay and changes the screen behind (opening a row) counts as no dismissal: the
report says it could not be checked. A tap that
changes the selected tab of a bottom tab bar ("See all" taking you to the Recipes tab) and lands on that tab's root
has its tab button as its way back: the report notes it and the walk returns by the button for the tab it started on.
The walk learns each tab's root once, from a fresh launch (up to two relaunches per tab, listed in the report). One that lands
anywhere else on that tab ("Open in Recipes" pushing a page) is checked like any other screen: a back control and an
edge swipe must each reach that tab's root. Tabs are told by their
place in the bar, and the tab bar is never part of a screen's identity, since the system renames its buttons once a
page has been pushed. The iPad sidebar, which lists tabs as cells, is not read as a tab bar. The fixture holds each
of these shapes beside a near miss that is a real bug (`testWhatIsNotABrokenWayBack`,
`testNearMissesOfWhatIsNotABrokenWayBack`). If a pick leaves the screen, the walk relaunches back rather
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
above any list row, so a missing pop gesture never fires a row's swipe action. If that moves nothing, a second edge
swipe goes beside the page's middle, at a height where nothing reaches the edge (any cell, keyed or not, and any short
scroll view, a carousel), and is not sent when every such height is taken: a zoom transition's pop does not start from
the bar's height (seen on iOS 27.2).

Before each gesture the walk waits for the screen to land (navigation bars and buttons holding still), since a push
still sliding in ignores a back swipe. It watches each gesture while the finger is down (a few of the screen's texts,
each with a label no other text on the screen has, for a swipe across; for a swipe down, the buttons in the screen's
navigation bar, else its texts). A gesture that does not return is sent once more, slower (a longer press, a slow
drag nearly across, a hold before letting go), because a loaded machine can drop a synthesized drag, so it moves
nothing, or rush it, so the screen starts to follow and settles back. If no gesture returns even then, the walk tells
two failures apart:

- **No way back.** A swipe moved the screen and, even sent slowly, it settled back where it was (a sheet that refuses
  a pull down). That is a bug found, as is a screen with no visible back control.
- **The gesture never arrived.** No swipe moved anything, even sent slowly, so no transition started. The screen is
  reported as not checked, because from outside the app a gesture that is off on that screen (a hidden system back
  button turns the edge swipe off) looks the same as a touch that never reached the app. Not checked still fails the
  run, and unlike other not-checked findings it is often a real bug: look at the screen before you rerun.

Run the walk on an iPhone simulator: on the iOS 27.2 iPad simulator it finds the visible way back, but its edge swipe
and swipe down did not return even from a plain push, so on iPad it reports missing gestures that a person would not
miss. Making the gestures work on iPad is planned for v0.2.

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

Proves: single taps, never retried, land at the centre and the four edges (4 pt in). A loaded machine can report a
change late, so a tap that has not landed within `within` gets twice as long again before it counts as a miss; one
that lands then is noted as late. A zero-length press
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
started had both taps land, or neither; one that ends changed lost a tap. Each pair is read once the control has held
still for a second (a loaded machine can apply the second tap late), never resent. It is read from where the control ends, so
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
feel.expect(film.doubleDraws(of: ["Pancakes"]))         // samples at most 0.5 s apart (maxGap:)
feel.expect(film.chrome(from: "bar.full", to: "bar.compact"))
feel.expect(film.settles("cook.cover", within: 1.0))
```

**What a film can and cannot see.** XCUITest waits for the app to go idle after every tap, so a film started by a tap
(`film(_:for:every:during:)`) sees what happens after the transition (late jumps, lingering chrome, ghost copies that stay),
not the frames inside it. To film a transition itself, run it on the app's own clock
(below), so the test decides when each frame happens. Timing it from launch is fragile: under load, launching took
longer than the delay and the film began after the motion. A check
that sees no motion says "could not check"; it never passes. Nor does a double-draw check whose samples were ever
further apart than `maxGap` (0.5 s by default) and saw no copy: a copy shown for less than the gap could be missed.

**A film on the app's own clock.** A film timed by the runner's clock gets thinner as the machine gets busier: on
hosted CI runners samples came over a second apart, and a motion due late (a jump 2 s after landing) fell past the
film's end. When the app's motion can run on a clock the test controls, film it with
`film(_:steps:tick:clock:advance:stall:during:)`: the app moves its timeline one `tick` each time `advance` runs (for
example `FeelClock.darwinNotification("my.app.tick")`, which the app observes with
`CFNotificationCenterGetDarwinNotifyCenter`) and shows its tick count in the element keyed `clock`. The film samples
once per tick, after the app shows the new count, and stamps each sample with the app's time, so a slow machine films
the same frames as a fast one. If the app stops answering for `stall` seconds (30 by default), the film ends there
(`FeelFilm.stalledAt`) and every motion check on it says it could not be checked. Its reports say they were timed by
the app's own clock (`FeelFilm.timedBy`), not the runner's. The fixture's motion page works this way (`FixtureClock`).

```swift
let film = feel.film(["motion.card", "bar.full", "bar.compact"], steps: 35, tick: 0.1, clock: "motion.clock",
                     advance: FeelClock.darwinNotification("bot.ouro.feel.fixture.tick")) { play.tap() }
```

**A film recorded inside the app.** Even on the app's clock, a film taken from the test cannot see a push, a sheet
or any system transition: XCUITest's wait for an idle app holds the test, not the app, and those transitions run on
Core Animation's media clock, which no test can step. So the app films itself. Link the `OuroFeelRecorder` product
into the app (a debug or test configuration is enough) and call `OuroFeelRecorder.installIfRequested()` once at
launch; it does nothing unless the test launched the app with `OuroFeel.recorderEnvironment`. Then:

```swift
app.launchEnvironment.merge(OuroFeel.recorderEnvironment) { $1 }
app.launch()
let film = feel.recordedFilm(["recipe.title"]) { app.buttons["Tomato Toast"].tap() }
feel.expect(film.snaps(of: "recipe.title", appearing: true))
feel.expect(film.settles("recipe.title", within: 0.8))
```

The test posts a Darwin notification; the app starts a `CADisplayLink` and, every frame it draws, writes down where
each named element is drawn: its accessibility frame carried from where its view is laid out to where the view's
presentation layer draws it (a push, sheet or zoom moves and scales the layer, not the view), and left out while a
layer above it is hidden or transparent. A key that shows twice in a frame (the same title on both pages of a push)
is sampled once, from the frontmost. The test taps and posts stop; the app ends the film once everything it watches has held still for half a
second, since a tap can return to the test while its transition is still moving. Each sample is stamped with the display link's own time, and the report says
so. In the fixture, a push filmed this way held 67 frames about 0.019 s apart with the title in 21
places (three runs), and a push with animations turned off showed the title in one place: the snap check caught it
([fixture](../../Examples/OuroFeelFixture/UITests/FeelCatchesTests.swift), `testAPushFilmedInTheApp`).

What it cannot do:

- **It runs on the simulator only.** The test and the app share a folder under the test runner's temporary
  directory, which a simulator app can reach and an app on a device cannot. On a device, `recordedFilm` waits
  `timeout` seconds and returns a stalled film, so every check on it says it could not be checked; it never passes.
- **Frames the app does not draw are not in the film.** While the app's main thread is busy (laying out a new page,
  for example) the display link does not fire, so the film has a long frame. A page that arrives in full across a
  frame shorter than `maxGap` (0.15 s by default) is a snap; a longer one cannot be judged and the check says so.
- **It sees UIKit-level motion, and SwiftUI's only through the accessibility frame.** Pushes, sheets, zooms and
  `UIView` animations move layers the recorder reads. An `.offset`, `.scaleEffect` or `.opacity` that SwiftUI
  applies inside its hosting view shows only as far as SwiftUI moves the element's accessibility frame, so put the
  identifier on the view that moves.
- **Walking the accessibility tree costs time each frame.** Name only the elements you judge; a long recording of
  many elements can slow the app it films. A film stops at 20 s and is then marked stalled, so no check passes on
  what came after.

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
film ended. `jumps` counts moves after the first one, so start the film before the transition. To see every
frame of a transition, record it inside the app (above).

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
  - launch › nav.settings: no gesture back (a swipe moved the screen, then it settled back where it was)
  measured: good=3, screens=4
  on simulator (iPhone 17 Pro, iOS 27.2), cold start (fresh simulator); timed by the test runner's wall clock, sampling accessibility snapshots
```

Every report names where it ran (simulator or device), how it started, and which clock timed it; a finding marked
`(inference)` goes beyond what was measured. A finding marked `(not checked)` is something the check could not judge
(the element was never on screen, samples were too far apart, the app was busy through a move, a swipe back moved
nothing even when sent slower): the check fails, its
summary starts "could not check:", and it is never counted as a bug (`result.detections` holds only the bugs). Fix the
test or rerun; do not report it as jank found. The one exception to look at first is a gesture back that moved nothing:
the gesture may be off on that screen (see the way back). Say the same when you quote it.

## Proof

`Examples/OuroFeelFixture` has one page per genre with a known bug behind `-bug 1`. Its UI tests
(`FeelCatchesTests`) prove each check fails on the bug and passes without it; CI runs them on every pull request.
