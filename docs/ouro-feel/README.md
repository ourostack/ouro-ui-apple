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

## Every app runs it

Every app built with Ouro UI links `OuroFeel` into its UI test target and runs a Feel walk in CI: every primary
screen, in every device posture the app supports (on an iPhone Duo: closed, open in portrait and open on its side; on
an iPad: portrait and landscape), with every check below that fits the screen. A reader also runs its place checks in
each reading mode (paged and scrolling).

When a person reports jank, the first job is the missing check: write the Feel check (or the step) that would have
caught it, see it fail on the bug, then fix the app and see it pass. If no check here covers it, add one (below, Add a
check). Gatefold build 39 is why: none of its four reports (a swipe and a top-edge tap that lost the place, a header
over the text, a text column off the side) was caught, because Gatefold never linked Ouro Feel.

## The principles

Ouro Feel holds an app to four promises. Each promise owns a set of checks, and the set is open: every time a person
meets jank no check caught, it gets a check of its own, named for the promise it keeps rather than for the bug. The
promises are `FeelPrinciple`, the checks `FeelCheck` (`FeelCheck.all`); a check's report carries its name
(`FeelResult.check`). The same list, as data, is [checks.json](checks.json), which ui.ouroboros.bot draws its Ouro Feel
page from; `CatalogTests` fails when the file falls behind the code.

1. **[Your intent is the unit](#your-intent-is-the-unit).** What you meant takes one go: one tap lands, one tap finishes
   what it started, and every way in has a way back out.
2. **[Your place is yours](#your-place-is-yours).** Where you are reading or working stays put through relaunches,
   turns, stray touches and late replies.
3. **[The content is the canvas](#the-content-is-the-canvas).** What you read fills its space and stays there: inside
   the window, still on every axis it doesn't scroll, and never covered or crowded out by chrome.
4. **[Motion and chrome never surprise](#motion-and-chrome-never-surprise).** Things move once, on purpose, at the
   display's pace: no ghost, no jump, no snap, no flicker, no stall.

The first fourteen checks were Ouro Feel's genres of jank (`FeelGenre`), and each is still a `FeelCheck`
(`FeelCheck(genre)`). That enum stays as it is so no app's code breaks; every check added since lives only in
`FeelCheck`.

The way back is the app-wide check: give it your entry points and it visits every screen it can reach by tapping
cells, links and buttons, checking each screen's layout on the way. Name the overlays to check; the motion and place
checks watch the elements and steps you give them.

## Add a check

A jank report no check caught is the usual start, and adding a check should take an afternoon, not a design review.

1. **Name the promise it keeps,** not the bug: "viewport holds still", not "the page drags sideways". Pick the
   principle it serves; if it serves none, that is a new principle, and worth a line in the decision record.
2. **Add it to `FeelCheck`** (`Sources/OuroFeelCore/FeelGenre.swift`): a `static let` with its name, what good feels
   like, its principle and its calls, and a line in `FeelCheck.all`. Adding to `FeelCheck` never breaks an app's code
   (`scripts/api-break.sh` agrees); `FeelGenre` stays closed.
3. **Judge it in `OuroFeelCore`,** a pure function from what was read to a `FeelResult` built with `FeelResult.judged`,
   with a unit test in `Tests/OuroFeelTests` for the bug, for its near misses and for what it cannot see ("could not
   check", never a pass).
4. **Read the screen in `OuroFeel`,** an `OuroFeel` method that drives XCUITest and hands what it read to the judge,
   with poses where layout can change.
5. **Prove it on the fixture:** a page in `Examples/OuroFeelFixture` with the bug behind `-bug 1`, and a test in
   `FeelCatchesTests` that sees it fail with the bug and pass without it. CI's last Feel shard runs any test the shard
   plan doesn't name, so a new test needs no plan edit.
6. **Write it down:** run `OURO_FEEL_WRITE_CATALOG=1 swift test --filter CatalogTests` to update `checks.json`, add its
   row
   to the principle's table above and its section below, and say where it came from.

Then run it on the app that showed the jank, see it fail there, and let that app's fix make it pass.

## Your intent is the unit

What you meant takes one go: one tap lands, one tap finishes what it started, and every way in has a way back out.

| Check | What good feels like | Call |
|---|---|---|
| the way back | Every screen you reach has a visible way back and a gesture back, and both return you where you were. | `feel.wayBack(from:follow:depth:)` |
| overlay dismissal | Every sidebar, popover and menu goes away with a tap outside it, and once you pick something in it. | `feel.overlays(_:)` |
| tap landing | One tap anywhere on a control works, every time, with no second try. | `feel.tapLanding(on:trials:spots:title:rowToggles:baseline:rapid:rapidBaseline:)`, `feel.osBaseline(rapid:)` |
| one action finishes the intent | A tap that starts slow work (a download, a load, a sign-in) finishes what you asked for when the work is done; you never tap it twice. | `feel.finishesIntent(_:opens:within:quiet:)`, `feel.finishesIntent(_:named:within:quiet:done:)` |

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
edge swipe must each reach that tab's root. A root is told by its navigation bar titles (by the whole screen when it has none), so it holds
while the root's content loads or is filtered; a page pushed there under the root's own title with its back button
hidden would be noted as a tab switch rather than failed. A pager taller than half the window at the leading edge is
not kept clear of the lower edge swipe. Tabs are told by their
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

### One action finishes the intent

Proves: one tap on a control that starts slow work (a download, a load, a sign-in) ends with what you asked for on
screen, with no second tap. It taps once, then waits up to `within` seconds (30 by default) for `opens` (an identifier
or label), or for your `done` to hold. The screen counts as busy while anything on it changes (words, values such as a
progress figure, frames) or a spinner or progress bar shows. Once it has held still, with nothing busy, for twice
`quiet` seconds (`quiet` is 3 by default; the second half is for work that runs on with nothing on screen to show it)
and the intent is not done, then if the same control is back, it taps that control once more: if the second tap finishes the intent, the first tap's work
was dropped when it ended, and the check fails. When the intent never finishes, even after a second tap, or the
control is gone once the screen settles, it could not check: the work may have failed in the test's state, or need
longer. So does an intent already done before the tap: name something only the finished intent shows (the open book's
page, not its title in the library). Launch into a state where the work is needed (the book not downloaded) and is
safe to repeat. Work that runs longer than twice `quiet` with nothing changing on screen reads as dropped, so show progress
while it runs, or raise `quiet`.

```swift
feel.expect(feel.finishesIntent(app.buttons["library.book.mobyDick"], opens: "reader.page"))
feel.expect(feel.finishesIntent(app.buttons["Sign In"], named: "signing in") { app.tabBars.firstMatch.exists })
```

From Gatefold, 2026-11-27: opening a book that was not downloaded downloaded it and stopped there, so it took a second
tap to open. The fixture's `intent` page has the same book (`testOneActionFinishesTheIntent`).

## Your place is yours

Where you are reading or working stays put through relaunches, turns, stray touches and late replies.

| Check | What good feels like | Call |
|---|---|---|
| place stability | Reopen, relaunch or turn the device and you are exactly where you were. | `feel.place(across:read:)` |
| place kept through stray input | A stray tap (the middle, the top edge), an edge swipe that goes nowhere, a swipe across and back, dismissing a sheet or leaving the app never moves your place. | `feel.placeHeld(across:reads:between:read:)`; for a reader, `across: FeelPlaceStep.strayReading` |
| navigation that fights you | After you move, your place stays where you put it: no late restore, re-sent jump or sync landing moves it again. | `feel.placeFights(_:reads:hold:between:read:)` |

### Place stability

Proves: the place (by default every static text on screen) reads the same after each step: `.background`, `.rotate`,
`.relaunch` (the default list), or `FeelPlaceStep("reopen") { feel in … }`. It stores and reports only the first 16
hex digits of a SHA-256 of what it read, never the content.

```swift
feel.expect(feel.place(read: { app.otherElements["reader.page"].value as? String ?? "" }))
```

`.relaunch` reuses `app.launchArguments`, so drop any reset arguments before calling it.

### Place kept through stray input, and navigation that fights you

Both read the place after every action and keep only fingerprints (`FeelPlaceTrail`), judged in reads, never seconds.
`read` names the place and nothing else (a location, a page number, the page's words) and returns an empty string while
the place loads; reading every text on screen would count the controls a stray tap shows as a moved place.

`feel.placeHeld(across:read:)` runs actions that must keep the place and fails if any read after one shows another
place, even if it later came back. The default steps are `.strayTap()` (the middle of the window, where a reader shows
or hides its controls; pass `at:` where the middle is a deliberate control), `.edgeSwipe` (the way back's own gesture,
for a screen where it is not a way back) and `.background`. Add `.noInput` to catch a late reply that moves the place
while you are idle, and `.sheetDismissed("Contents", sheet: "contents.title") { app in … }` for a sheet opened and
swiped away (a sheet that never opened or closed could not be checked).

Two more steps are for a reader, and `FeelPlaceStep.strayReading` adds them to the stray ones:

- `.topEdgeTap()` taps the very top of the window, where the status bar is. iOS scrolls a scroll view to its top on
  that tap (`scrollsToTop`), so a reader that scrolls jumps to the start of the chapter. Turn it off on the reading
  view.
- `.swipeAcrossAndBack` swipes left across the middle, then right. On a page that scrolls up and down a sideways swipe
  is stray; on a paged one it turns the page and back. Either way you must end where you started: a reader that
  changes chapter on the first swipe must bring you back to your place, not to the chapter's start or end.

Both lost Ari's place in Gatefold build 39's scroll mode.

`feel.placeFights(_:reads:hold:read:)` runs your own moves. After each one the place must land (the first place two
reads in a row agree on, so a page that shows a place for one read on its way is fine), where you chose when the move
says (`.move(step, landsOn: "Chapter 3")`), and hold for at least `hold` reads. Going back to where you were, even for
one read, is a late restore; moving on after landing is a re-sent or late jump; landing elsewhere than you chose is an
input queued during a jump. Give it enough `reads` to outlast your app's restore or sync, and `between:` to advance an
app on its own clock between reads.

```swift
let place = { app.otherElements["reader.page"].value as? String ?? "" }
let turn = FeelPlaceStep("next page") { feel in feel.app.swipeLeft() }
feel.expect(feel.placeHeld(across: FeelPlaceStep.stray + [.noInput], read: place))
feel.expect(feel.placeFights([turn, turn], read: place))
```

## The content is the canvas

What you read fills its space and stays there: inside the window, still on every axis it doesn't scroll, and never
covered or crowded out by chrome.

| Check | What good feels like | Call |
|---|---|---|
| inside the window | Every control and what you read sits wholly inside the window, in every orientation and after turning the device and back; no header, bar or control covers the text or sits under the status bar. | `feel.insideWindow(poses:also:)`, `feel.uncovered(by:content:within:poses:)`; also on every screen `wayBack` reaches |
| viewport holds still | Nothing pans on an axis it doesn't scroll, and no content is wider or taller than its viewport on an axis that is fixed, in every pose. | `feel.viewportHolds(scrolling:poses:)` |
| chrome floats over content | Glass and overlays float over the content: it runs underneath them, never shrinks or is cropped to make room, and its end can always be brought clear of them. | `feel.chromeFloats(_:over:content:toEnd:poses:)` |

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

With `also:`, the elements you name (identifiers or labels) must lie inside the window too: what you read, such as a
page's text column, which is no control. Gatefold build 39's text column slid past the side of the open iPhone Duo
while every control stayed inside. A named element not on screen in a pose could not be checked there. Name one
element (a page's frame), not something a pager repeats on every page, whose copies past the side would count as
outside.

```swift
feel.expect(feel.insideWindow(poses: [.current], also: ["reader.page"]))
```

### Covered content

Proves (part of the inside-the-window genre): none of the chrome you name (headers, bars, buttons that float over the
page) covers any of the content, and none sits under the status bar. The content is what you name in `content:`, or,
by default, every static text and image on screen that is not chrome or inside it. Frames that overlap by a point or
less do not count. Content may scroll under the status bar; only chrome must keep clear of it. Content outside the
window is left to `insideWindow`, since a paginated book keeps its next column past the side on purpose. The status
bar is read from the system only when it lies along the top of the app's window; when it is hidden (a reader with its
controls away) or reported in another orientation's coordinates, the report notes that chrome under it was not
checked, and the rest is still judged. A chrome element, a named piece of content or the `within` element that is
not on screen could not be checked, so name only what shows in the poses you pass. `within:` limits the content to
what is inside one element (a reader's page), so a test probe or a toast elsewhere is not counted. Content with no
identifier is named in the report by a fingerprint of its words, never the words.

The default content suits a reader. On a list whose rows scroll under a translucent bar you name as chrome, a row
passing under the bar would count as covered: name the content, or use `within:`.

```swift
feel.expect(feel.uncovered(by: ["reader.runningHead", "reader.close"], within: "reader.page"))
```

From Gatefold build 39: its running head sat over the first line of text on the folded iPhone Duo, and its controls
sat under the status bar on the open one.

### Viewport holds still

Proves: in each pose (portrait, landscape and portrait again by default, as `insideWindow`), no scroll view, web view
or the window pans on an axis it does not scroll, and no content is wider or taller than its viewport on an axis that
is fixed. Two readings judge it:

- **Content past a fixed edge.** Every text, image and control drawn in a viewport (not in a viewport inside it) must
  lie within the viewport's sides when it scrolls only up and down, and within its top and bottom when it scrolls only
  sideways. Content in the window, outside any scroll view, must lie within the window both ways. A line wider than its
  page is a page a finger can pan, or one that is cut off.
- **A drag along a fixed axis.** It drags across each viewport along every axis that it and every viewport around it
  leave fixed: leftward, from three quarters of the way across to under a third, and upward, so the drag is never the
  system's back swipe or a sheet's pull down. It watches up to four of the viewport's texts (and two of the window's,
  since a page that pans as a whole carries its chrome along) every tenth of a second while the finger is down, and
  once it has lifted. Content that moved more than 2 pt along the drag's axis panned, even if it sprang back.

A drag never starts in a viewport inside the one it judges (a carousel in a list: there the list scrolls the way the
carousel doesn't, so no axis is fixed), nor on a switch, slider, picker or field. A list is never dragged sideways,
and no sideways drag starts or ends on a row: a row slides to show its swipe actions, and a full swipe fires one,
which in a real app may delete something. So a list's sideways hold is judged by its overflow alone, and a list that
is the largest viewport never makes the drags could-not-check. A drag that changed what was on screen (most of what it watched was gone: a page turn, a new
screen) is noted as the app's own gesture and not judged, and ends that pose's drags. A viewport no drag could cross
(too small, or covered by what is inside it) is said in a note; when that is the largest viewport and nothing was
dragged at all, the check could not check.

Accessibility does not say which way a scroll view scrolls. A web view and a list of rows scroll up and down; another
scroll view scrolls sideways when its content runs past its sides and nowhere past its top or bottom, and each piece
past the sides is no wider than the viewport (a carousel's cards, a pager's next page in the tree), and up and down
otherwise: a line wider than its page is never a card. Declare a viewport the guess gets wrong, by
identifier or label in `scrolling:`. Findings on a guessed axis are marked as inference, and the report lists which were guessed. Run
it on a screen at rest, with no sheet up, since a sheet's drag moves it on purpose.

```swift
feel.expect(feel.viewportHolds())                                        // portrait, landscape, portrait again
feel.expect(feel.viewportHolds(scrolling: ["reader.pager": .horizontal], poses: [.current]))
```

From Gatefold, 2026-11-27: the reading page could be dragged sideways, cutting off the text's left edge, while every
check passed (Ari: "being able to mess with viewport is very much something ouro feel should be catching"). The
fixture's `viewport` page scrolls both ways with lines wider than the window in its bug build, and holds a sideways
shelf inside a page that scrolls up and down in both (`testViewportHoldsStill`).

### Chrome floats over content

Proves: in each pose, each piece of chrome you name (a glass pill, a floating bar, a button over the page) floats over
the content's viewport rather than beside it, and once the content is brought to its end, its last line lies wholly
inside the viewport and under none of that chrome.

- **At rest,** each piece of chrome must sit over the viewport: its middle inside the viewport's frame. Chrome whose
  middle is outside it, beside the viewport's edge, has taken that room from the content, and the report says how much.
- **At the end,** the content's last line (the lowest text or image in the viewport) must lie wholly inside the
  viewport and the window, on every side, and under none of the chrome. By default the check swipes up the viewport until that line holds still
  for two swipes, up to 15; pass `toEnd:` to bring it there yourself (a book's last page). Content that kept moving
  could not be checked.

`over:` names the viewport (a reader's page, a scroll view); by default it is the largest scroll view or web view on
screen. The content is every text and image inside it that is not chrome, or what you name in `content:`. Content with
no identifier is named by a fingerprint of its words, never the words. Chrome not on screen could not be checked, so
name only chrome that shows at rest. The chrome's frame is the one accessibility reports, so give a pill its padding
inside the button's label (`Button { Text(…).padding(…) }`), not outside the button, or the glass drawn around the
words is not seen. The fixture's own pill, padded outside its button, passed its bug build that way ([run 46030232275](https://github.com/ourostack/ouro-ui-apple/actions/runs/46030232275)). Lines in the middle of the page passing under the chrome are how floating works,
and are not judged; only the end must come clear. To do that, give the scroll content a bottom margin the height of the
chrome (`.contentMargins(.bottom, …, for: .scrollContent)`), and put the chrome in an overlay rather than a stack.

```swift
feel.expect(feel.chromeFloats(["reader.restart"], over: "reader.page"))
```

From Gatefold, 2026-11-27: a Liquid Glass "start from the beginning" pill shrank the reading area and hid its last
lines, instead of floating over the text. The fixture has both halves: `float`, whose bug build stacks the pill under
the page (`testChromeFloatsOverContent`), and `float-under`, whose bug build floats it with no room at the end
(`testChromeLeavesTheEndClear`).

## Motion and chrome never surprise

Things move once, on purpose, at the display's pace: no ghost, no jump, no snap, no flicker, no stall.

| Check | What good feels like | Call |
|---|---|---|
| double-draw | Each piece of content is on screen once; nothing shows a ghost copy mid-transition. | `film.doubleDraws(of:)` |
| jump after landing | Once something lands it stays put; nothing nudges it afterwards. | `film.jumps(of:rest:limit:)`; at an open, from pixels, `feel.screenFilm(...).revealHolds(cover:until:)` |
| late or lingering chrome | Bars and controls hand over in one beat: never two states at once, never a blank between them. | `film.chrome(from:to:grace:)` |
| snap with no transition | Things that move travel there; nothing teleports across the screen. | `film.snaps(of:distance:appearing:)` |
| settle time | The screen comes to rest promptly after you act. | `film.settles(_:within:)` |
| flicker | Each thing changes once on its way to where it ends; nothing flips back and forth before it settles. With no input, nothing changes at all. | `film.flickers(of:within:changes:)`; for the whole screen, `feel.screenFilm(...).flickers(within:states:)`; with no input, `feel.stillWhileIdle(for:watch:poses:)` |
| hitches (a measure) | Motion runs at the display's pace with no visible stall. | `FeelHitches.analyze(timestamps:refresh:)`, `film.hitches()`, `feel.measureHitches(in:)` |

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
is sampled once, from the frontmost, unless the test asks for every copy
(`recordedFilm(keys, copies: true)`, ouro-ui-apple 0.3.5 or later in both the test and the app; an older recorder
films one copy, and a pass on it proves nothing). Then `doubleDraws` counts copies on every frame the app draws,
stamped by its display clock rather than wall-clock snapshots; a frame the app drops is still a gap, and a gap
longer than `maxGap` still cannot be judged. Copies that overlap by half or more read as one drawing, so a keyed
container that only partly covers its keyed view reads as a second copy: key one of them. The test taps and posts stop; the app ends the film once everything it watches has held still for half a
second, since a tap can return to the test while its transition is still moving. Each sample is stamped with the display link's own time, and the report says
so. In the fixture, a push filmed this way held 67 frames about 0.019 s apart with the title in 21
places (three runs), and a push with animations turned off showed the title in one place: the snap check caught it
([fixture](../../Examples/OuroFeelFixture/UITests/FeelCatchesTests.swift), `testAPushFilmedInTheApp`).

**Without linking it into the app.** Xcode links a package product into every configuration of an app, Release
included, so a linked recorder ships inert in the App Store build. To keep it out, link the
`OuroFeelRecorderInjectable` product into the UI test target instead, drop the app's call, and launch with
`OuroFeel.injectedRecorderEnvironment`. That loads the recorder into the app with `DYLD_INSERT_LIBRARIES`, on the
simulator only, and it installs itself once the app runs (if the app still calls `installIfRequested()`, only the
first recorder installs). It is nil off the simulator or when the test bundle carries no such library;
merge it in only when it is there, or the films stall and every check on them says it could not be checked:

```swift
if let recorder = OuroFeel.injectedRecorderEnvironment {
    app.launchEnvironment.merge(recorder) { $1 }
}
```

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

### Flicker

Proves: each named element changes once on its way to where it ends. It fails when an element blinks (shown, hidden,
shown, or the reverse, with the middle run at most `within` samples), when its words are taken back (A, B, A) or change
more than `changes` times within `within` samples, or when it leaves a resting place by more than `distance` points (seen
in at least one sample) and rests there again within `within` samples. A spring that overshoots never rests on its way,
so it is no flicker. Everything is counted in samples, never seconds, so `within`'s span in time follows the film's
clock: the default 30 is half a second recorded in the app and 3 s on a 0.1 s app tick (lower it for a film with a
short toast). The words are the accessibility label, not the value, and a page that shows "Loading" between two pages
changes twice. It could not be checked when an element was still changing in the film's last `hold` samples, or when
nothing flickered but samples were once more than `maxGap` (0.15 s) apart, so film it in the app (`recordedFilm`) or on
the app's own clock.

```swift
let film = feel.recordedFilm(["reader.location"]) { app.swipeLeft() }
feel.expect(film.flickers(of: ["reader.location"]))
```

**The whole screen, from pixels.** Content no element names (a web view's page, a canvas) can still flicker: the
screen shows A, then B, then A again where no label ever changes. `feel.screenFilm(steps:tick:clock:advance:)` takes
one screenshot per tick of the app's own clock, shrinks each to a 160-pixel grayscale thumbnail, and blanks the status
bar, the clock's label and any rect in `ignoring` (a slip the app means to show and take away). `flickers(within:states:)`
cuts the film into rests (at least 2 samples, each under 0.6 mean absolute difference from the rest's first), labels
each by its settled picture (rests under 1.5 apart share a label), and fails when:

- a label comes back after another within `within` samples (default 90, counted in ticks; the element check's 30 counts
  frames);
- the screen flashes away from a rest and back in samples too short to rest (one tick is plain to see), or reaches the
  next rest for a moment, goes back, then on again;
- the action rests in more than `states` different states (default 2, which covers a toggle; a contents jump that shows
  a veil, then the page, declares 3).

Frames between two different rests are otherwise not judged: a slide or scroll of real content is as far from both rests
as they are from each other, so pages spun through on the way to a new page are not caught here; judge such a page's
place with the element check. It cannot be checked when the clock stalled, when a sample came more than twice the usual gap after the last (a skipped
tick could hide a flash), when the pictures differ in size, or when the screen was still changing at the end. Only motion
that follows the app's clock is filmed deterministically: a web view's CSS or WebKit's own fades run on wall time, so
film those from a recording. The screenshot follows the accessibility tree's tick and can lag it by a frame on a slow
runner, so give each state a few ticks.

```swift
let film = feel.screenFilm(steps: 12, tick: 0.1, clock: "reader.clock",
                           advance: FeelClock.darwinNotification("app.tick")) { app.swipeLeft() }
feel.expect(film.flickers())
```

**Seeing what was judged.** Record a screen film's result with `feel.record(result, name:, screenFilm: film)`. When it
fails, a contact sheet is saved beside the report, as an attachment and in `OURO_FEEL_REPORT_DIR`: every sample in
order, a white strip under each sample that is part of a rest and a black one under each on its way or flashing
(`film.contactSheet()`), with the film's JSON.

### Still while idle

Proves (part of the flicker genre): with no input for a few seconds (`for:`, 3 by default), no enabled control and
nothing named in `watch:` (chrome that is no control, such as a running head) appears, goes or moves by more than half
a point, and the status bar neither shows nor hides. It looks at the screen as often as accessibility snapshots allow,
so a loop of a few changes a second fails within the first few looks. Call it once the screen has landed. A status bar
the system does not report is noted, and the controls are still watched.

```swift
feel.expect(feel.stillWhileIdle(for: 3, watch: ["reader.runningHead"]))
```

From Gatefold's reader on the open iPhone Duo (2026-11-15): with no touch, its close button and the status bar took
turns several times a second, and the controls jumped between two places. Showing or hiding the status bar changes the
safe area, which moved the chrome, which flipped the status bar again.

### The first page shown after an open holds

`film.revealHolds(cover:until:)` is jump after landing at an open, judged from the same screen film as whole-screen
flicker. `cover` is a picture of the cover (a launch screen, a placeholder, a picture of the page) taken while it is
surely up, with `feel.screenPicture(clock:)`: the judge never guesses which rest is the cover, since a film that started
after the cover had gone would take the wrong first page for it and pass the very jump this is for. The first thing the
screen rests on after the cover must be what it rests on up to sample `until` (the next scripted mark, not itself
included; the film's end by default): another rest after it, the cover coming back, or a flash away and back fails. It
catches a wrong first page even when the app's own report of the place is right, as on Gatefold build 20's relaunch,
which showed another page for about 10 s and then jumped to his. Counted in samples. It cannot be checked when no rest
looks like the cover (start the film while it is up), when nothing but the cover rests, or when the screen is still
changing at `until`. Only what follows the app's clock is filmed deterministically; a relaunch's wall-time wait needs a
clock the app keeps through it.

```swift
let cover = feel.screenPicture(clock: "reader.clock")!
let film = feel.screenFilm(steps: 40, tick: 0.1, clock: "reader.clock",
                           advance: FeelClock.darwinNotification("app.tick")) { app.buttons["Open"].tap() }
feel.expect(film.revealHolds(cover: cover))
```

### A screen film for an app with no clock of its own

An app that runs on the system's animations (UIKit transitions, a web view, a reader engine such as Readium) has no
clock a test can step, so it can't use the films above without a test-only seam in its own code.
`feel.screenFilm(reads:atLeast:settle:during:)` films it as it plays instead: one screenshot per XCUITest read, as fast
as they come, shrunk and blanked as the clock film's are (the status band and `ignoring`). It reads for at least
`atLeast` seconds after the action, then stops once the last `settle` reads look the same, or after `reads` reads. Set
`atLeast` past the slowest step you expect, so a page that rests a moment before it jumps is filmed when it jumps.
`flickers(within:states:)` and `revealHolds(cover:until:)` judge it in reads. The film is marked `byReads`: an uneven gap
between reads is how screenshots go, so it is not a reason the film can't be checked, and `timedBy` says how many reads
covered how long. A flash shorter than one read is not seen, so this is weaker than a film on the app's clock: use the
clock where you have one. Take the cover with `feel.screenPicture()`. The fixture's `reveal-reads` page is the same open
as `reveal`, run on wall time (`testRevealHoldsByReads`).

```swift
let cover = feel.screenPicture()!
let film = feel.screenFilm(atLeast: 4) { app.buttons["Open"].tap() }
feel.expect(film.revealHolds(cover: cover))
```

Or let the film shoot its own cover. With `cover: true`, either screen film first takes a picture of the screen as it
is, before the action, with the film's own size and blanking, and keeps it in `film.cover`. `film.revealHolds()` then
judges against it. A cover taken separately with other settings can only make the judge say "could not check", so
this way the two always compare. Start the film while the cover is up.

```swift
let film = feel.screenFilm(cover: true, atLeast: 4) { app.buttons["Open"].tap() }
feel.expect(film.revealHolds())
```

### Hitches

`FeelHitches.analyze(timestamps:refresh:)` turns display-link timestamps (from a probe in your app, such as the HX
gallery's `FrameProbe`) into a hitch ratio: under 5 ms/s is good, over 10 is critical (WWDC20, "Eliminate animation
hitches with XCTest"). `feel.measureHitches(in: self) { … }` wraps `XCTHitchMetric` (iOS 26 and later); its figures go
to the result bundle. On the simulator these numbers are a proxy that depends on the Mac; gate on a device.

A film the app made on its own display (`FeelRecording`, one sample per frame) carries its own timestamps:
`film.hitches()` reads them, at the film's own pace unless you pass `refresh:`, and names the longest stall in one
finding ("the app stalled 0.567 s at 1.133 s, 33 refreshes late (limit 2)"). Use it beside the motion checks, which
judge how something moved and so can pass while the app froze around it. A film not made by the in-app recorder is not
one sample per frame, so it could not be checked.

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

`Examples/OuroFeelFixture` has a page for each check with a known bug behind `-bug 1`. Its UI tests
(`FeelCatchesTests`) prove each check fails on the bug and passes without it; CI runs them on every push to `main` and
every release (the required "Ouro Feel catches every genre's bug").
