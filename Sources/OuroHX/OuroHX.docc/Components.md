# Components

Button, EmptyState, Banner, Sheet and Toast: the same five components as Ouro HX for web, drawn in SwiftUI and at
their best with no options: capsule buttons that answer on touch-down, Liquid Glass toasts and sheet controls on iOS
26, and springs you can interrupt everywhere.

## Overview

A small settings screen with a main action, an empty state and a confirmation toast:

```swift
import OuroHX
import SwiftUI

@main
struct NotesApp: App {
    var body: some Scene {
        WindowGroup {
            SettingsScreen()
                .ouroToaster()       // once, at the root: shows toasts sent from anywhere below
                .ouroTheme(.pearl)   // outermost, so the toasts are themed too
        }
    }
}

struct SettingsScreen: View {
    @Environment(\.ouroToast) private var toast
    @State private var devices: [String] = []

    var body: some View {
        VStack(spacing: 16) {
            if devices.isEmpty {
                OuroEmptyState("No devices yet", systemImage: "iphone", description: "Sign in on another device to sync.")
            }
            OuroButton("Save settings", systemImage: "checkmark", fullWidth: true) {
                toast("Settings saved", tone: .success)
            }
        }
        .padding()
    }
}
```

| Web | Apple | What it is |
|---|---|---|
| `Button` | ``OuroButton``, ``OuroButtonStyle`` (`.buttonStyle(.ouro())`) | Any action. Tones, variants (`solid`, `soft`, `outline`, `plain`, `glass`), sizes and a `pill` shape. `role: .destructive` draws the destructive tone. |
| `Empty` | ``OuroEmptyState`` | What a list or page shows when it has nothing in it. |
| `Alert` | ``OuroBanner`` | An inline message in the page. On Apple an "alert" is SwiftUI's modal `.alert`, so it is a banner here. |
| `Sheet` | `.ouroSheet(isPresented:title:…)` | A panel from the bottom edge with a title, a body, an actions row and a close button. |
| `toast`, `Toaster` | `@Environment(\.ouroToast)`, `.ouroToaster()`, ``OuroToast`` | A short message that VoiceOver reads once and that dismisses itself. |

`OuroEmpty` and `OuroAlert` are not types: they are unavailable names whose compiler error names the Apple one.

### What every component promises

These are the eight claims in ouro-ui-core's [`standard/hx/components.md`](https://github.com/ourostack/ouro-ui-core/blob/main/standard/hx/components.md),
vendored here as `OuroHXTesting`'s `components.claims.json`. `Tests/OuroHXTests/ClaimCoverageTests.swift` fails when a
claim has no test here.

- **44-point targets** on a touch screen (`target.touch`): every size of ``OuroButton``, and every close, dismiss
  and action control. With a pointer, buttons step down to desktop density (28, 32 and 40 points).
- **No motion under Reduce Motion** (`motion.reduced`): no press scale, banners and toasts crossfade instead of
  unfolding or sliding, and a sheet appears without sliding up. A toast still follows a finger dragging it. See
  ``OuroAppearance``.
- **VoiceOver names and traits** (`name.spoken`): titles are labels and headings, icons are decorative and hidden,
  close buttons are named ("Close", "Dismiss"; pass your own words to translate them).
- **Large text wraps** (`text.reflows`): no label, title or message has a line limit; at the accessibility sizes an
  empty state's action spans the width and a toast's action moves under its words.
- **Contrast** (`contrast.text`): every label reads at 5:1 on what is behind it in all six themes, light and dark,
  and 7:1 under Increase Contrast. That is a margin over WCAG's 4.5, because Xcode's audit measures antialiased
  pixels. A glass button's label is measured against the page's background; over a photo, check it yourself. The
  palettes (``OuroButtonPalette``, ``OuroBannerPalette``, ``OuroToastPalette``,
  ``OuroEmptyStatePalette``, ``OuroSheetPalette``) raise a theme colour only where it falls short.
- **Announcements by urgency** (`announce.urgency`): destructive banners and toasts and warning banners interrupt
  VoiceOver; the others, warning toasts included, wait. See ``OuroTone/announcementPriority(for:)``.
- **A toast with an action waits** (`toast.action-stays`): it stays until dismissed unless you give it a duration.
  Any toast's countdown waits while VoiceOver, Switch Control or a pointer is on it, and starts over when they leave.
  Up to three toasts show at once, one at the accessibility text sizes, so a stack never hides the screen. Toasts
  show above an open `.ouroSheet`, and one sent with the id of a toast already showing replaces it as a new
  showing: VoiceOver hears it and its countdown starts over.
- **A banner speaks once** when it arrives, and again only when its words change, not each time it scrolls back
  into view.
- **A close control** (`dismiss.reachable`) on every sheet, dismissible banner and toast.

### In your own screen

What the components don't do for you, and how to match them:

- **Your own text.** The components raise their text to 5:1 on whatever is behind it; a theme pair such as
  `mutedForeground` on `card` is not promised to reach that. Pass your own secondary text through
  ``OuroColor/readable(_:on:contrast:)`` with the environment's `colorSchemeContrast`.
- **Rows and switches.** There is no row or toggle component yet. Use SwiftUI's `Toggle`, `Form` or `List` with the
  colours from `\.ouroColors`, and give each row at least `\.ouroTouchTarget` points of height.
- **A screen that is the whole app.** `.ouroToaster()` and `.ouroTheme(_:)` can go on the screen itself instead of in
  `@main`; `@Environment(\.ouroToast)` only reaches views inside the toaster, so send from a child view. A toaster
  inside another one takes over for the views inside it.
- **Disabled buttons** all look the same: a muted chip with an outline and a label that still reads at the target,
  not web's half opacity, which Xcode's audit fails. SwiftUI tells VoiceOver they are dimmed. A `loading` button is
  disabled too but keeps its tone: it is busy, not unavailable.
- **Auditing.** In a UI test, `OuroHXTesting`'s `ouroAccessibilityAudit()` runs Xcode's audit and excuses only the
  "Text clipped" it reports inside a sheet that iOS draws at 96% (``OuroSheetMetrics/drawnScale``), a sheet below
  full height on iOS 26 and later, which it recognises by its close button being drawn small. That leaves real
  clipping there unchecked, so audit the sheet once more at full height: present it with `detents: [.large]` from a
  launch argument your app reads.

### How they move and look

Everything moves on springs (``OuroMotion``), never fixed durations, so a change mid-way turns around from where it
is instead of jumping. The defaults are the designed version; options are for the exceptions.

- **Buttons** are capsules at every text size, 50 points tall at the medium size (34 drawn small, 56 large, each
  with at least a 44-point target); a label wrapped onto several lines rounds its corners at 44 points. Outlines
  are drawn in their tone at 50%, secondary's in the page's foreground at 25% (two points of the full tone under
  Increase Contrast), and an icon sits on the label's first line. A plain button's words sit on the layout margin,
  its target still 44 points. A press answers on touch-down: it shrinks to 97% on a quick spring and springs back with a
  little bounce. A plain tap plays no haptic; pass `haptic:` for a moment that earns one.
- **An empty state** is open, like the system's `ContentUnavailableView`: a 60-point hierarchical symbol (44
  inline, at most 80 at large text sizes) that bounces once as the state cascades in, line by line, 40 ms apart, semibold in the theme's secondary
  colour, so the title carries the state and an action the colour; a bold title and a line of description in a 340-point column. `variant: .outline` draws a dashed
  edge, for a drop zone.
- **A banner** is a soft tint with a fine edge in its tone (two points of the full tone under Increase Contrast),
  16-point corners; its words
  are the page's own colours and the tone is in the wash and the icon. Give it
  `isPresented:` rather than an `if` around it: changed inside `withOuroAnimation(.layout, …)` it folds away at its
  top edge as the page closes up, its words gone by 60% of the way, and unfolds again, turning around smoothly if changed mid-way. A stack's spacing
  still leaves a gap where a folded banner was.
- **A sheet** is the system sheet on the theme's surface (its raised popover colour in dark), with a solid 44-point
  close disc and a Title 2 title, a hairline rim in dark, and a grabber only when it has several heights to drag between.
- **Toasts** are 56-point glass capsules over the theme's surface, edged with a hairline and casting one soft shadow, at the top centre, at most 420 points wide, that drop in on a
  bouncy spring that visibly overshoots and lift away without one, shrinking to 96%. The icon grows with the words. Swipe one up to dismiss it; dragged down, it gives a little and comes back. Up to three stack,
  the older ones shaded a step deeper and tucked 12 and 22 points behind the newest with only a hairline edge and no shadow of their own, their words
  fading in 0.1 s as they tuck, so two sets of words never share a place. A tucking toast keeps its own size until the newest is measured,
  then takes that size on the arrival's spring, and older toasts fade out as the stack empties. Each keeps its own glass edge. A tap fans them out, and VoiceOver and Switch Control see them
  fanned out from the start; the region's "Show all" action fans them out for Voice Control and Full Keyboard
  Access. The glass sits over the theme's opaque surface, so the page never reads through, and the words take the
  system's vibrant label styles; under Increase Contrast or Reduce Transparency, and before iOS 26, the toast is solid
  with an edge, in the theme's colours. An action is tinted words after a hairline, not a button in the capsule. A toast's icon bounces as it lands; give
  one its own with `systemImage:`.

The measurements, and the apps they were studied from, are in decision 15 of `docs/decisions/2026-11-04-hx-components.md`.
Radii elsewhere come from the theme (``OuroTheme/radius(_:)``).

### Where they came from

- ``OuroButton``'s `glass` variant and `pill` shape: Spoonjoy's `KitchenTableActionButtonStyle` (capsules on
  interactive Liquid Glass, labels that wrap at accessibility sizes) and Gatefold's glass buttons (`.glassProminent`,
  `glassEffect(.regular.interactive())`).
- ``OuroEmptyState``: Spoonjoy's `KitchenTableEmptyTile` (a heading title, a hidden icon, a full-width action at the
  accessibility sizes) and Gatefold's `EmptyShelf` (centred, one action).
- ``OuroBanner``: Spoonjoy's `HeldChangeBanner` (a titled message with its way out) and web's `Alert`.
- The sheet and the toast follow web's `Sheet` and `Toaster`; neither app had a toast.

## Topics

### Button

- ``OuroButton``
- ``OuroButtonStyle``
- ``OuroButtonVariant``
- ``OuroButtonSize``
- ``OuroButtonShape``
- ``OuroButtonPalette``
- ``OuroButtonMetrics``
- ``OuroColor/readable(_:on:contrast:)``

### Empty state

- ``OuroEmptyState``
- ``OuroEmptyStateAlignment``
- ``OuroEmptyStateVariant``
- ``OuroEmptyStatePalette``

### Banner

- ``OuroBanner``
- ``OuroIcon``
- ``OuroBannerPalette``
- ``OuroBannerMetrics``

### Sheet

- ``SwiftUICore/View/ouroSheet(isPresented:title:description:hideTitle:detents:closeLabel:onDismiss:content:footer:)``
- ``OuroSheetPalette``
- ``OuroSheetMetrics``

### Toast

- ``OuroToast``
- ``OuroToaster``
- ``OuroToastAction``
- ``OuroToastDuration``
- ``OuroToastQueue``
- ``OuroToastPalette``
- ``OuroToastMetrics``

### Shared

- ``OuroTone``
- ``OuroToneComponent``
- ``OuroAnnouncementPriority``
- ``OuroAppearance``
- ``OuroInput``
