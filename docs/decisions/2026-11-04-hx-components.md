# 2026-11-04: Ouro HX for Apple's first components

Status: accepted (W8 of the HX and AX native program).

## Decision

1. **Five components, web's set:** `OuroButton`, `OuroEmptyState`, `OuroBanner`, `.ouroSheet` and the toast
   (`OuroToast`, `@Environment(\.ouroToast)`, `.ouroToaster()`). Each mirrors the web component of the same job, and
   its DocC article says which.
2. **Names.** Web calls two of them `Empty` and `Alert`. This repository's AGENTS.md names them `EmptyState` and
   `Banner`, and on Apple an "alert" is SwiftUI's modal `.alert`, so they are `OuroEmptyState` and `OuroBanner`.
   `OuroEmpty` and `OuroAlert` are unavailable `renamed:` type aliases, so the compiler points web's name at ours.
3. **Behaviour is claims, proven here.** ouro-ui-core v0.3.0's `standard/hx/components.claims.json` states eight
   claims (44-point targets, Reduce Motion, VoiceOver names, reflowing text, contrast, announcement urgency, a toast
   with an action waits, a reachable close). Reduce Motion stops animated movement; a drag may still follow the
   finger, though here the toast fades in place instead. `OuroHXTesting` vendors the file by hash, and `ClaimCoverageTests` fails
   if a claim has no Swift test here. The proofs: pure tests of each component's metrics and palettes (every theme,
   light and dark, standard and increased contrast), snapshot references, and gallery UI tests running
   `performAccessibilityAudit` on every component page at the default and the largest accessibility text size.
4. **Contrast by construction.** Each component resolves its colours as a palette value (`OuroButtonPalette` and
   friends) and raises a label to 5:1 (7:1 under Increase Contrast) on what is actually behind it, rather than
   trusting a theme pair. Pearl's solid primary needs no raising; the derived increased-contrast colours sometimes do.
   The target is 5:1, not WCAG's 4.5: the audit measures antialiased pixels and read a soft warning button and a
   banner description at exactly 4.5:1 as "Contrast nearly passed". Where even white or black can't reach it on a
   solid fill, the fill moves away from the label. A toast's shadow is drawn by its surface alone and
   stays inside the gap above it: on the whole toast it shaded every glyph, and reaching the toast above it shaded
   that one's words, and the audit read both as failed contrast, even for black text.
5. **Spacing is web's metrics** until core has a spacing token: a medium button is 44 points tall with 16 at its sides
   (web's `h-11 px-4`). A spacing token is a core follow-up, web first.
6. **Touch and pointer.** On a touch screen every button is at least 44 points. With a pointer (macOS) buttons take
   web's desktop heights (28, 32, 40) and are at least 24 points wide, WCAG 2.5.8's minimum; the claim names touch.
7. **Reduce Motion.** No press scale; banners and toasts crossfade (`OuroAppearance.fade`) instead of sliding; a sheet
   appears without its slide (`disablesAnimations`) and its content fades in.
8. **Glass and pill** are a variant (`.glass`, Liquid Glass from iOS 26 and macOS 26, a material before) and a shape
   (`.pill`), from Spoonjoy's and Gatefold's buttons. Web's defaults stay: solid, rounded.
9. **The toast is an environment action**, not a binding per screen: `.ouroToaster()` once at the root owns the queue
   (`OuroToastQueue`, a value type with web Toaster's rules: three show (one at the accessibility text sizes, where
   three would cover the page and hide its text, which the audit flagged), a destructive toast waits ahead of others, an
   id replaces in place), and any view sends with `toast("Saved")`. Without the root modifier, sending logs the fix.
10. **Snapshots are kept per host macOS major** (`Tests/OuroHXTests/__Snapshots__/macOS-26`, `macOS-27`): text
    renders differently on each. Pull-request CI sets `OURO_SNAPSHOT_RECORD=never` and uploads `.actual.png` files,
    which are the source for the macOS 26 references. `ImageRenderer` draws no Liquid Glass, no `ScrollView`
    content and nothing inside `accessibilityFocused` (the toast's snapshot turns its focus tracking off), and macOS
    has no Dynamic Type, so those are proven on iOS by the gallery tests and captures.

11. **Toasts show above sheets.** The root `.ouroToaster()` owns the queue; an open `.ouroSheet` draws the toasts
    instead of the root while it is the newest open sheet, as web portals its Toaster above dialogs.
12. **A toast's countdown waits while someone is on it**: VoiceOver or Switch Control focus on any part, or a pointer
    over it, as web pauses on focus and hover; it starts over when they leave. A replacement under the same id is a
    new showing, announced and timed afresh. The model, not the view, remembers which showings were announced and
    when each goes, so a toast drawn again in another host (a sheet opening or closing) is heard once and keeps its
    time; a closing sheet hands the toasts back as it starts to close.
13. **A banner speaks once** on arrival and again only when its words change, not on every `onAppear`.
14. **From the agent-usability run** (a fresh agent building a settings screen from the docs alone, against
    v0.3.0-rc.1). Its screen compiled and used the components correctly, and its own audit run found two library
    problems: a disabled solid button at web's half opacity failed contrast, and the fitted sheet's 96% scale failed
    as "Text clipped" in an app's audit, not only in the gallery's. So a disabled button of any tone and variant is a
    muted chip with an outline and a readable label (`OuroButtonPalette(…, isEnabled: false)`; some themes' tones are
    close to their muted grey, so the outline and fill carry it, not colour alone), a loading button keeps its tone,
    and `ouroAccessibilityAudit` excuses "Text clipped" only on an element wholly inside an `.ouroSheet` (`ouro.sheet`)
    whose close button (`ouro.sheet.close`) is drawn smaller than its 46-point layout size: measured, not guessed from
    the sheet's height, so nothing is excused on macOS, before iOS 26, or in a sheet at full height
    (`OuroAuditExcuse`, unit-tested). The agent also
    had to guess how to make its own muted text read, so `OuroColor.readable(_:on:contrast:)` is public, and the
    article gains "In your own screen".

15. **Beautiful by default** (Ari, 2026-11-04: an app using the components with no options should look its best;
    "OK", "clean" and "polished" all fail). The first cut copied web, and on Apple it looked like web. Each component
    was rebuilt against a reference board of Apple's own apps and the best third-party ones (kept with the desk's
    W8 evidence), and every transition is recorded frame by frame and probed for hitches in the gallery
    (`MotionTests`). What changed, and why:
    - **Springs, not web's curves.** Core's motion tokens are CSS easings for the web; SwiftUI's springs carry
      velocity through an interruption, which a fixed curve cannot. `OuroMotion` gains `pressIn` (0.15 s, no
      bounce), `pressOut` (0.35 s, 0.15), `enter` (0.55 s, 0.25), `exit` (0.35 s, none), `settle` and `layout`. Core's
      durations still set the Reduce Motion crossfade.
    - **Capsule buttons**, 34/50/56 points drawn, every one at least 44 points to touch, semibold body type: the
      shape of iOS 26's own buttons. The ends are circular, not continuous (a continuous corner at half the height
      reads slightly square), and a capsule at every text size: the radius is half the height drawn, up to 44 points,
      so a two-line label at the accessibility sizes is a rounded rectangle, not an oval. The icon is a step smaller
      than the words; soft fills are 14% of the tone in light and 26% in dark; outlines are the tone at 40%, not the
      neutral border, so an outline row reads as its tones. Press is scale only, on touch-down; no haptic on a plain
      tap (Apple's apps keep haptics for moments, not taps).
    - **An open empty state** like `ContentUnavailableView`, not web's dashed card: boxed empty states read as a web
      page on Apple. The dashed edge stays as `.outline`, for drop zones. Standing alone, its 60-point symbol is the
      one note of the theme's primary colour; with an action it is the secondary colour, so the action is the one
      thing to look at. It grows with Dynamic Type up to 80 points; inline (`.leading`) it is 44 points and sits on
      the page's own margin.
    - **A borderless banner** that folds in place (`isPresented:`), never sliding over what is above it. An `if`
      around it made a removal transition that could not turn around: the frame captures showed it jump when hidden
      and shown again mid-way, and a stalled frame at the turn when only its frame height animated. One animatable
      fold value drives height, scale and opacity, so it retargets on the spring; its words are gone by halfway, so
      the page closing up never slides over words still showing. In dark a 15% tint washes the raised card colour.
      The words are the page's own colours (tinted descriptions read as a web alert), the neutral banner's icon is
      secondary, icons and close glyphs stop growing at the largest standard size, and at the accessibility sizes
      the words get the whole width.
    - **A glass toast at the top**, where iOS puts its own (AirPods, Silent mode, Apple Pay), hugging its words, with
      a stack that tucks behind the newest as Sonner and iOS's notification stacks do. Its countdown stays 5 s and
      its close control stays visible: the board and both taste rounds suggested 2.5 s and no close button, but
      `toast.action-stays` and `dismiss.reachable` ("every toast") win; the glyph is a quiet bold caption. An action
      is tinted semibold words after a hairline, as the system's Undo is, not a button inside the capsule.
    - **A solid close disc on the sheet**, which sits on the theme's popover colour in dark so it has an edge over the
      dimmed page. A sheet with one height has no grabber, as Apple's own don't. The sheet keeps the theme's surface on iOS 26 too: its text and the
      components in it are made readable on that surface, and the system's glass is not it (`contrast.text` wins
      over translucency). The toast's glass sits over the theme's opaque surface too, so the page never reads
      through; its words take the system's vibrant `.primary` and `.secondary`, which the gallery's audit measures in
      light and dark. Theme colours inside the glass dropped a frame on every departure (5 of 5 in the frame
      captures, against 0 of 5 for vibrant), so they go with the solid surface only.
    - **A glass toast over an opaque surface, with a shadow**: the glass alone read as a grey smudge on a white
      page, and at 55% and 85% tints the accessibility audit still measured the page's words through it, so the
      theme's surface sits wholly behind the glass and casts the shadow; the glass gives the rim light and depth.
      The shadow is light (black 8%, 12-point blur, 4 down) and the front toast's alone. Tucked toasts are solid, peek
      8 then 14 points at 95% and 90%, and draw only their surface: hidden words left in the accessibility tree were
      found by the audit as clipped, faint and under 44 points. Their words fade out as they tuck rather than
      vanishing first; a blank plate showed for two or three frames in round 2's captures, and in round 3's until
      the surface stopped switching view branches as a toast went solid. The audit helper excuses "Contrast failed"
      only on page content a toast partly covers and on an element more than half off screen (`OuroAuditExcuse`).
      Each toast's own frame counts, so in an expanded stack every toast's words still fail, and the gallery audits
      the stack expanded too. On glass, a toast's words are the system's vibrant ones only where those read on the
      theme's surface; a custom theme whose popover does not suit the colour scheme gets a solid toast.
    - **The stack under Reduce Motion** is not scaled, and toasts take their places without sliding there.
    - **The taste panel decides.** Two independent reviewers, one comparing with Apple's own apps and one with fresh
      eyes, judge each component from captures and frame sequences. Rounds 1 and 2 said no to every one; these
      changes are theirs (W8 evidence `taste/`). Declined, with reasons recorded there: a 15-20% toast tint (the
      audit read the page through 55% and 85%), white labels on core's bright dark-mode solids (they fall short of
      5:1; raised with core), the system's glass behind sheets (the theme's words are made readable on a known
      surface, and theme colours on glass dropped frames), and a zoom morph from the source button (it needs an API
      change). Round 3 said no again, and round 4 adopted: opaque tucked plates shaded 4% and 8% (fading them let
      the page show through), a hairline edge on every toast, a symbol bounce as a toast lands, a toast's own
      `systemImage`, a stronger secondary solid, outlines at 50% (full tone, two points, under increased contrast),
      icons on a label's first baseline, an empty state that cascades in (40 ms a line, from its settled look, so a
      still render shows it whole; `.drawOn` starts hidden and was declined for that), banners edged in their tone
      with 20-point corners and a Title 3 icon, and a 44-point sheet close disc with a Title 2 title. The audit of the
      expanded stack excuses two readings it gets wrong there, with the proof in the test: Undo "fails contrast" even
      drawn black on white, and the oldest toast's plain words read as an undersized target; the toasts' buttons are
      asserted at 44 points and hittable instead. Round 4 said no again and found a bug the snapshots could not:
      the keyframed cascade drew the empty state's symbol at the screen's origin on device. Round 5 drops the
      keyframes (each line is held clear for the frame before arrival, then springs in), adds a UI test that reads the
      symbol's pixels above its title, and adopts: a toast landing that visibly overshoots (0.5 s, bounce 0.32), an
      exit to 96%, a deeper shadow, an icon that grows with the words, peeks of 12 and 22 points, secondary's outline
      at 25% of the foreground, plain buttons on the margin, a 12% dark secondary step, 16-point banner corners and a
      dark sheet rim. Round 5 said yes to the sheet and the toast (both lenses). For the rest, round 6 fixes a stack
      bug the strips showed (a tucking toast took the new toast's size before it was measured, so it vanished for
      an arrival's first frames), tucks plates with a hairline and no border, clears a folding banner by 60%, grows
      banner icons as toast icons grow, makes the empty state's symbol secondary and semibold, shows the glass
      buttons first over a faint field, and lays plain buttons 24 points apart. The audit misreads words on glass
      buttons as it does Undo on the glass toast: it failed white "Primary" on near-black glass, and raising every
      glass label to 6:1 made it fail more, not fewer, so that change was undone.
      Round 6's stack first dropped one or two frames on every arrival, where round 5 dropped none: the older toast
      turned solid on the same frame the new toast's glass first drew. Measured by host video at 60 fps over 2 to 4
      runs each: keeping tucked toasts on glass (their opaque plate already hides the page) left one drop; tucking on
      the frame after the newest is measured (`stackDepth`, since removed) cleared the arrivals but left one as the
      stack emptied; fading tucked toasts out, not lifting three glass toasts at once, and one `GlassEffectContainer`
      for the stack brought light to no drops and dark to one. Removing the words' fade on tuck, or the fade out,
      made it worse. The remaining drop was the tuck itself: the front toast's first size, which tucks the stack, was
      set outside any animation, so the tuck snapped in one frame (words gone, plate resized and moved), dropped it
      in light and dark, and left a blank plate for about 130 ms before the new toast showed. That size now lands on
      the arrival's spring (`OuroToastMetrics.resizesTuckedOnMeasure`). Keeping the words mounted while hidden did not clear it.
      Round 6's panel said yes to five of six; both lenses said no to the stack. The older toast's words faded on the
      arrival's 0.5 s spring, so for a moment two sets of words shared a place. And one `GlassEffectContainer` merged
      the tucked plate and the front toast into one lumpy shape at rest. Round 7 fades a tucking toast's words in
      0.1 s on their own clock (`wordsFadeSeconds`), tucks on the arrival itself rather than the frame after the
      measurement (the tucked toast keeps its own size until then, so it never vanishes), and drops the container,
      so each plate keeps its own glass edge. Measured over three light and three dark runs, every arrival had no
      drops. It also grows the toast's close mark to Accessibility 3, as the banner's does, and gives the
      gallery's glass field real colour in dark, where dark glass read as flat grey over near-black (light stays pale:
      over a saturated warm field, glass Success and Warning measured 4.8:1, under 5:1). The toast's close frame grows
      with its mark, so the mark isn't clipped. Round 7's first pass had one no, lens B's on the empty state: its
      layered magnifier drew two-tone under hierarchical rendering and sank into a dark page, so every symbol is now
      one tone (`.monochrome`), and its one bounce on arrival was shown in a dense strip. Then both lenses said yes
      to all six. At the accessibility sizes, where one toast shows and nothing tucks, the words keep the plain fade:
      with the quick one, the stack of three becoming one left words the audit read as clipped, though none showed.
      On CI's hosted VM, which has no GPU, a failing transition is measured up to three times. The press alone is
      reported there against the same 5 ms/s limit, but not gated: it stalled 49 ms on release in every try, and is
      clean in the simulator and in the host-video captures (#25). On the buttons page, contrast on a glass button is excused and
      measured instead from the screen's pixels (`glassMisreadings`, `inkContrast`). The gallery shows the components over real content (a recipe list)
      rather than on grouped card backgrounds, which would box every section.
    - **Hitches are measured, not eyeballed.** `FrameProbe` (gallery only) counts late frames with a display link and
      marks each window with an os_signpost interval; `MotionTests` fails a transition above 5 ms of hitch per second
      or any frame two refreshes late. `XCTOSSignpostMetric` reports hitches on a device only, so that test skips
      on the simulator. Frame timing on a simulator follows the Mac's load, so the gate runs on CI's fresh hosted VM in
      Release, and a failing transition is measured once more before it fails. Each demo plays once unmeasured
      first (`-warm 1`): on CI's GPU-less VM the first glass a process draws stalled 180 to 415 ms on every launch,
      which a Mac's simulator never showed, so CI gates what every play costs and the host-video captures time the
      first play. Ouro Feel's motion genres (double-draw, jump after landing, settle) check the stack too
      (`FeelTests`), dogfooding the tool that judges apps built on the kit.

## From Spoonjoy's adoption (W10)

- **Named springs.** `OuroMotion.Kind` gains `snappy`, `smooth`, `bouncy` and `interactive`, at Apple's own preset
  values, for an app's own motion; they crossfade under Reduce Motion like every kind but press.
- **`turned` at full strength.** It took Gatefold's 0.7 (Gatefold doesn't import OuroHX); Spoonjoy found it too faint
  for a step turned mid-cook. It is a light impact at full strength.
- **The cookbook's dark page (#15).** Both values are meant: `background` is the web kit's `--background`
  (`--sj-paper`, #1f1d1a), copied byte for byte by core's parity, and Spoonjoy's page is `--sj-page` (#1e1c19),
  which OuroHX carries as `sidebar`. A single page colour would start in the web; nothing changes in core or here.

## Prior art

| Find | What it does | Verdict |
|---|---|---|
| [Apple HIG: Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) | 44 by 44 point minimum hit region; prominence by style, not size | **Adopt**: the 44-point claim and the role-driven destructive tone |
| [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Reduce Motion means replace sliding with fades; Dynamic Type must not truncate | **Adopt**: `OuroAppearance.fade`, no line limits, actions full width at accessibility sizes |
| [SwiftUI `ContentUnavailableView`](https://developer.apple.com/documentation/swiftui/contentunavailableview) | The system's empty state (iOS 17): label, description, actions | **Borrow** its three slots and the header trait; **ignore** using it directly, since it can't take a theme's colours or web's outline variant |
| [SwiftUI `.sheet` and presentation modifiers](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:)) | System sheet, detents, drag indicator, background | **Adopt**: `.ouroSheet` is a system sheet, so swipe-down, VoiceOver escape and detents come free; we add the title, close button and fitted height |
| [AccessibilityNotification.Announcement](https://developer.apple.com/documentation/accessibility/accessibilitynotification/announcement) with `accessibilitySpeechAnnouncementPriority` | Spoken announcements with high, default and low priority | **Adopt**: `announce.urgency` maps destructive banners and toasts and warning banners to high, as web's Alert and Toaster do |
| [XCUIApplication `performAccessibilityAudit`](https://developer.apple.com/documentation/xctest/xcuiapplication/performaccessibilityaudit(for:_:)) | Xcode's audit: hit regions, contrast, descriptions, Dynamic Type, clipped text | **Adopt**: it is the gallery tests' main proof |
| [microsoft/fluentui-apple](https://github.com/microsoft/fluentui-apple) | Fluent for iOS and macOS: `Button` styles over a token layer, `Notification` (a toast-like bar), `BottomSheet` | **Borrow** per-component token resolution (our palettes); **ignore** its UIKit-first views and its own bottom-sheet controller, since the system sheet now does the job |
| [material-components-ios](https://github.com/material-components/material-components-ios) (archived) and Material SwiftUI ports | Material buttons, snackbars, banners | **Borrow** the snackbar rule that an action keeps it up and only one action per toast; **ignore** Material's look |
| [shadcn/ui Sonner](https://ui.shadcn.com/docs/components/sonner) / [emilkowalski/sonner](https://github.com/emilkowalski/sonner) | Web's toast: `toast()` from anywhere, one `<Toaster/>`, visible limit, swipe to dismiss | **Adopt** the shape, as web did: `toast(...)` from the environment, `.ouroToaster()` at the root |
| [elai950/AlertToast](https://github.com/elai950/AlertToast), [exyte/PopupView](https://github.com/exyte/PopupView) | Popular SwiftUI toast and popup packages, bound per view with `isPresented` | **Ignore** the per-view binding: one queue at the root keeps web's limits and announcement order; **watch** PopupView's drag handling |
| [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | Snapshot strategies, per-OS reference folders by convention | **Borrow** reference folders per OS; **ignore** the dependency, since `OuroSnapshot` already renders in every appearance |
| [Apple HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion) and WWDC23 "Animate with springs" | Springs keep velocity through interruption; `duration` and `bounce` | **Adopt**: every component moves on a spring (decision 15) |
| [Apple: Explore UI animation hitches](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app) | Hitch ratio in ms per second; under 5 good, over 10 critical | **Adopt**: `MotionTests`' limit |
| iOS 26 system toasts (AirPods, Silent mode) and notification stacks | Top-centre glass capsules; older items tuck behind | **Borrow** the place and the tuck; **ignore** hiding the close control, for `dismiss.reachable` |
| [cashapp/AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot) | Snapshots of the VoiceOver element tree | **Watch**: a natural next proof for `name.spoken` once it supports SwiftUI-only hosts well |
