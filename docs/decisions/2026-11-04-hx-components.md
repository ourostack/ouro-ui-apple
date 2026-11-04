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
    as "Text clipped" in an app's audit, not only in the gallery's. So a disabled button draws the muted colours with a
    readable label (`OuroButtonPalette(…, isEnabled: false)`), and `ouroAccessibilityAudit` excuses "Text clipped"
    only inside an `.ouroSheet` (identified as `ouro.sheet`) that is below 90% of the window's height. The agent also
    had to guess how to make its own muted text read, so `OuroColor.readable(_:on:contrast:)` is public, and the
    article gains "In your own screen".

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
| [cashapp/AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot) | Snapshots of the VoiceOver element tree | **Watch**: a natural next proof for `name.spoken` once it supports SwiftUI-only hosts well |
