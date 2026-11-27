# 2026-11-27: Ouro Feel holds principles, each with an open set of checks

Status: accepted. Extends [2026-11-05: Ouro Feel](2026-11-05-ouro-feel.md), decision 2 (genres, app-wide).

## Context

On 2026-11-27 Ari found three bugs in Gatefold's reader that no Feel check caught: the reading page could be dragged
sideways, cutting off the text's left edge; a Liquid Glass "start from the beginning" pill shrank the reading area and
hid its last lines instead of floating over the text; and opening a book that wasn't downloaded needed a second tap
once it had downloaded. Ari: "being able to mess with viewport is very much something ouro feel should be catching,
and idk if the site is accurate but trying to fit the ouro feel checks into a neat list of 10 is very silly".

The site said "Ten genres, named and checked" while `FeelGenre` already had more, and the guide's single table had
no place a new kind of jank obviously belonged.

## Decision

1. **Principles, each with an open set of checks.** `FeelPrinciple`: your intent is the unit; your place is
   yours; the content is the canvas; motion and chrome never surprise (and, since
   [the jank-hunt follow-up](2026-11-27-ouro-feel-jank-hunt-checks.md), posture changes re-lay out in place). Every check (`FeelCheck`) names the principle
   it holds. The set under each grows with every report no check caught; a principle is added only when a report
   breaks a promise none of these make.
2. **Checks are named by the invariant, not the bug.** The three new checks are viewport holds still
   (`feel.viewportHolds`), chrome floats over content (`feel.chromeFloats`) and one action finishes the intent
   (`feel.finishesIntent`).
3. **`FeelCheck` is open; `FeelGenre` is closed.** Adding a case to a public enum breaks every app that switches over
   it (`scripts/api-break.sh` reports it), so `FeelGenre` keeps the cases it has and each is also a `FeelCheck`. A
   new check is a `static let` on `FeelCheck` and a line in `FeelCheck.all`, which breaks nothing.
4. **The list is data.** `docs/ouro-feel/checks.json` is `FeelCatalog.current`, and `CatalogTests` fails when it falls
   behind the code or when the guide's principle tables leave a check or a call out. ui.ouroboros.bot's Ouro Feel
   page draws its principles and checks from that file, so the site never states a count again by hand.
5. **Adding a check is cheap and expected.** The guide's "Add a check" is six steps, each with its file; the fixture's
   catch-all shard runs a new test with no plan edit.

## Prior art

Checked 2026-11-27.

| Prior art | Verdict | What we take |
|---|---|---|
| Ouro check's `off-screen` rule (ourostack/ouro-ui, `registry/ouro/check/layout-check.ts`: `pageScrollsAcross`) | borrow | A page that scrolls across is judged by what is drawn past its edge, on the axis it shouldn't scroll |
| [WCAG 2.2 SC 1.4.10 Reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html) | borrow | Content that scrolls one way needs no scrolling the other way; two-axis scrolling is the failure |
| [Lighthouse "Content is sized correctly for the viewport"](https://developer.chrome.com/docs/lighthouse/pwa/content-width) | borrow | Content wider than its viewport is a finding by itself, before any drag |
| [Apple HIG, Liquid Glass and materials](https://developer.apple.com/design/human-interface-guidelines/materials) | adopt | Controls float in a layer above content, which runs beneath them |
| SwiftUI `safeAreaBar(edge:)` (iOS 26) and `contentMargins(_:_:for:)` (iOS 17) | adopt | The fix the chrome check expects: chrome in a layer over the scroll view, room at the content's end |
| [Nielsen Norman Group, "Visibility of system status"](https://www.nngroup.com/articles/visibility-system-status/) | borrow | Slow work shows progress, and ends where the person was going |
| Feel's own `FeelGestureProgress` (the way back's watch of a gesture while the finger is down) | adopt | The same run-loop timer reads the viewport's content mid-drag |
| [Maestro `waitForAnimationToEnd`](https://docs.maestro.dev/api-reference/commands/waitforanimationtoend) | borrow (inverted, as before) | Wait for a still screen; a screen that settles with the intent undone is the finding |

## Consequences

- Apps adopt the three checks from the release that carries them, in the Feel walks they already run in every posture.
- A finding on a viewport whose axis was guessed is marked inference; an app declares its pagers with `scrolling:`.
- Still to add: the viewport check inside the way-back walk (overflow only, no drags) so every reached screen gets it;
  a drag rightward where the screen has no back gesture; a horizontal end for chrome over a sideways pager; and a check
  that a tap's slow work survives leaving and coming back.
