<!-- ourostack:brand:start -->
<p align="center">
  <a href="https://github.com/ourostack"><img src="https://raw.githubusercontent.com/ourostack/.github/main/brand/headers/ouro-ui-apple.webp" alt="Ouro beside a phone, a tablet and a laptop all showing the green Ouro HX card, with a small robot pressing a button" width="100%"></a>
</p>
<!-- ourostack:brand:end -->

# Ouro UI for Apple

**SwiftUI components for people and App Intents for agents.** Ouro HX and Ouro AX, in Swift: the same colours, motion and manners as
[ui.ouroboros.bot](https://ui.ouroboros.bot/), now on iPhone, iPad and Mac, plus the bits that make an app pleasant for Siri and
every other agent that comes knocking.

[ui.ouroboros.bot](https://ui.ouroboros.bot/) · [Releases](https://github.com/ourostack/ouro-ui-apple/releases) · [Ouro UI core](https://github.com/ourostack/ouro-ui-core) · [Ouro Reins](docs/ouro-reins/README.md) · [More from Ouro](https://github.com/ourostack)

## Install

```swift
// Package.swift
platforms: [.iOS(.v18), .macOS(.v15)],
.package(url: "https://github.com/ourostack/ouro-ui-apple.git", from: "1.4.0"),

// your target
.product(name: "OuroHX", package: "ouro-ui-apple"),
```

iOS 18 and macOS 15 or later, Swift 6.1 (Xcode 16.3 or later). Newer things (the iPhone Duo's hinge, Siri AI) switch on by themselves where the
OS has them.

Build it with Xcode. The Command Line Tools alone can't: `swift build` stops at SwiftUI's own macros (`@Entry`, `@State`), whose
plugin only Xcode has.

**Status:** 1.0. The public API is source-stable: a source break waits for 2.0 (see [Source stability](#source-stability)). The newest release is on [Releases](https://github.com/ourostack/ouro-ui-apple/releases/latest). What 1.0 required (eighteen components, claims, platforms, API stability and adoption) is in [docs/decisions/2026-11-14-apple-1-0.md](docs/decisions/2026-11-14-apple-1-0.md). Meets core [v0.14.0](https://github.com/ourostack/ouro-ui-core/releases/tag/v0.14.0): the tokens and the claim sets (AX's
`apple.claims.json`, HX's `components.claims.json`) are core's, byte for byte, and CI checks it.

### A first screen

A settings screen with a validated field, a checkbox, a segmented control and a confirmation sheet. It is a whole app: put it in
your app target, or in `Sources/<YourApp>/App.swift` of a package with the lines above. CI builds it from this README as a new
app, for the Mac and the iOS Simulator (`scripts/readme-app.sh`).

```swift
import OuroHX
import SwiftUI

enum Appearance: Hashable { case system, light, dark }

struct SettingsScreen: View {
    @Environment(\.ouroToast) private var toast
    @State private var name = ""
    @State private var email = ""
    @State private var news = true
    @State private var appearance: Appearance = .system
    @State private var nameError: String?
    @State private var emailError: String?
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OuroTextField("Display name", text: $name, error: nameError, required: true)
            OuroTextField("Email", text: $email, error: emailError, type: .email, required: true)
            OuroCheckbox("Email me about new features", isOn: $news)
            OuroSegmentedControl("Appearance", selection: $appearance, items: [
                OuroSegment("System", value: .system),
                OuroSegment("Light", value: .light),
                OuroSegment("Dark", value: .dark),
            ])
            OuroButton("Save", systemImage: "checkmark", fullWidth: true) { save() }
            OuroButton("Delete account", systemImage: "trash", tone: .destructive, variant: .outline, fullWidth: true) {
                confirmDelete = true
            }
        }
        .padding()
        .preferredColorScheme(appearance == .system ? nil : appearance == .dark ? .dark : .light)
        .ouroSheet(isPresented: $confirmDelete, title: "Delete your account?", description: "This removes your settings for good.") {
            EmptyView()
        } footer: {
            OuroButton("Delete", systemImage: "trash", tone: .destructive) { confirmDelete = false }
        }
    }

    private func save() {
        nameError = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter a display name." : nil
        emailError = email.contains("@") ? nil : "Enter an email address, such as jo@example.com."
        if nameError == nil, emailError == nil { toast("Settings saved", tone: .success) }
    }
}

@main
struct SettingsApp: App {
    var body: some Scene {
        WindowGroup { SettingsScreen().ouroToaster().ouroTheme(.pearl) }
    }
}
```

## One system with web

Ouro UI is one system with a web half and an Apple half, and each half has a side for people (Ouro HX) and a side for agents (Ouro AX). This package is the Apple half.

| | Web ([ourostack/ouro-ui](https://github.com/ourostack/ouro-ui)) | Apple (this package) |
|---|---|---|
| People (Ouro HX) | React components you copy into your app with the shadcn CLI | `OuroHX`: `OuroButton`, `OuroBadge`, `OuroCard`, `OuroItem`, `OuroTextField`, `OuroSegmentedControl`, `OuroCheckbox`, `OuroSeparator`, `OuroDescriptionList`, `OuroAvatar`, `OuroSkeleton`, `OuroSpinner`, `OuroProgress`, `OuroPageHeader`, `OuroEmptyState`, `OuroBanner`, `OuroSyncStatus`, `.ouroSheet` and toasts, the spring, the press, haptics and six themes; `OuroFeel` checks how it feels |
| Agents (Ouro AX) | a kit for command lines, HTTP APIs and MCP servers, and an X-ray that calls them from outside | `OuroAX` outcomes shaped like web's, an X-ray for an app's App Intents (`ouro-ax-xray`), and `OuroReins` to drive its screens |
| Both, from one declaration | a command line, MCP and WebMCP tools and a web control | an App Intent, a SwiftUI button and a Reins action |

Both halves read the same tokens from [ouro-ui-core](https://github.com/ourostack/ouro-ui-core), and both prove ouro-ui-core's component claims with tests of their own. Where a claim has a web test but no Apple test, or the other way round, the [parity table](https://ui.ouroboros.bot/apple/#parity) on the site says so, and it is built from core's claim files, not typed by hand.

### One declaration, every surface

Ouro UI's [one action model](https://github.com/ourostack/ouro-ui-core/blob/main/docs/guides/actions.md) (ouro-ui-core v0.5.0, [decision record](https://github.com/ourostack/ouro-ui-core/blob/main/docs/decisions/2026-11-13-agents-use-agent-interfaces.md)) lets an app declare an action once in TypeScript. Core's `ouro-actions.mts generate` writes the action's command line, MCP and WebMCP tools and web control, and for this package an App Intent and a SwiftUI `Button(intent:)` in `OuroActions.swift`, and a Reins action in `OuroActionsReins.swift` (they build against `OuroReins`). `ouro-actions.mts check` fails the app's CI when a generated file differs from its declaration, so a surface that drifts is caught in CI. The generator is core's, copied into your app; this package does not contain it.

## What's in the box

| Product | For | What it has |
|---|---|---|
| `OuroHX` | your app | the components: `OuroButton` (solid, soft, outline, plain, glass; rounded or pill), `OuroBadge` (solid, soft, outline), `OuroCard` (outline or plain), `OuroItem` and `OuroItemGroup` (rows and lists of them), `OuroTextField` (a labelled field with its keyboard, autofill, error and show password), `OuroSegmentedControl` (one of a few views, 44 points to touch), `OuroCheckbox` (checked, not or mixed), `OuroSeparator` (a line, with words in it or not), `OuroDescriptionList` (terms and their details), `OuroAvatar` (a picture or initials in a hue that matches web's, with presence), `OuroSkeleton`, `OuroSpinner` and `OuroProgress` (loading, known and unknown), `OuroPageHeader` (a page's or section's title, eyebrow, description, actions and picture), `OuroEmptyState`, `OuroBanner`, `OuroSyncStatus` (saved, saving, offline, not saved, with Retry), `.ouroSheet`, and toasts (`.ouroToaster()` at the root, then `@Environment(\.ouroToast)`); `.ouroTheme(.pearl)`, `ouroColors` and radii in the environment; `OuroColor` (contrast, increased contrast, adaptive colours); `OuroMotion` (core's spring and curves, polite under Reduce Motion); `OuroHaptics` (one named table of moments); `OuroFoldPosture` and `OuroFoldReader` (tabletop, book, closed) |
| `OuroHXTesting` | your tests | `OuroSnapshot` (light, dark, increased contrast), `ouroAccessibilityAudit`, `OuroDuoHinge` (fold the Duo simulator from a UI test) |
| `OuroAX` | your app | `OuroAX.Outcome` and `OuroAX.Problem` (web's `ax-outcome` and `ax-problem`, field for field), exit codes, entity queries with fuzzy matching, `OuroAXOutcomeIntent`, `OuroAXPackage` |
| `OuroAXTesting` | your tests | Siri evaluation wordings and pass rates; the App Intents X-ray's checks, reports and Siri scenario sets (`AXXray`) |
| `ouro-ax-xray` | you and CI | X-rays a built app's App Intents against Ouro AX for Apple's claims: `swift run ouro-ax-xray --app path/to/App.app --out report` |
| `OuroAXTestingProbe` | the X-ray's test plan | runs the X-ray's behaviour stage with AppIntentsTesting ([Templates/XrayProbe](Templates/XrayProbe)) |
| `ouro-ax-skills` | you and CI | lints `Skills.skillsbundle` for Siri: `swift run ouro-ax-skills lint path/to/Skills.skillsbundle` |
| `OuroAXSkillsLintPlugin` | your build | the same lint at build time, with errors pinned to the line |
| `OuroFeel` | your UI tests | checks how the app feels, one per genre of jank: the way back, overlay dismissal, inside the window, tap landing, double-draw, jumps, chrome, snaps, settle and place ([Ouro Feel](#ouro-feel-how-it-feels-measured)) |
| `OuroFeelCore`, `OuroFeelRecorder`, `OuroFeelRecorderInjectable` | Ouro Feel's internals | the measurements, the in-app recorder, and the same recorder as a library a UI test loads into a simulator app so the app never links it |
| `OuroReins` | your app's UI-free core, its tests and agents | every screen as state and actions, driven with `ls` and `do` headless or over a debug-only socket; journeys; a network guard that fails any request ([docs/ouro-reins/README.md](docs/ouro-reins/README.md)) |
| `OuroA2UI` | your app, when an agent composes UI for a person | `A2UISurface`: Ouro HX's [A2UI](https://github.com/a2ui-project/a2ui) catalog in SwiftUI, where every button is one of your declared actions and pressing it follows its consent class; `A2UI.validate` and `A2UI.resolve`, and `ComposedTree` for a tree that came another way, ported from core and proved against core's conformance cases ([agent-composed UI](#agent-composed-ui-a2ui)) |
| `ouro-devicehub` | a Mac CI job | presses Device Hub's buttons: `dump`, `press "Partially Open"`, `serve <dir>` |

```swift
import OuroHX

struct SettingsScreen: View {
    @Environment(\.ouroToast) private var toast

    var body: some View {
        VStack(spacing: 16) {
            OuroEmptyState("No devices yet", systemImage: "iphone", description: "Sign in on another device to sync.")
            OuroButton("Save settings", systemImage: "checkmark", fullWidth: true) {
                toast("Settings saved", tone: .success)
            }
        }
        .padding()
    }
}

// At the root, once:
SettingsScreen().ouroToaster().ouroTheme(.pearl)
```

Every component keeps 44-point targets, crossfades under Reduce Motion, has VoiceOver names, wraps at the largest
text sizes and reads at 5:1 (7:1 with Increase Contrast): ouro-ui-core's
[component claims](https://github.com/ourostack/ouro-ui-core/blob/main/standard/hx/components.md), each proven by a
named test here (`Tests/OuroHXTests/ClaimCoverageTests.swift`). The DocC article "Components" has the details.

Building your own control instead? The tokens are in the environment:

```swift
import OuroHX

struct Card: View {
    @Environment(\.ouroColors) private var colors
    @Environment(\.ouroTheme) private var theme
    @State private var saved = false

    var body: some View {
        Button(saved ? "Saved, splendidly" : "Save") { saved.toggle() }
            .foregroundStyle(colors.primaryForeground)
            .padding()
            .background(colors.primary, in: .rect(cornerRadius: theme.radius(.lg)))
            .buttonStyle(.ouroPress)
            .ouroHaptic(.checked, trigger: saved)
    }
}

```

A theme's own tokens, such as Cookbook's `sj-*` colours, shadows and text roles, are in `theme.extras`
(`OuroTokens.swift` in core v0.4.0). A text role picks the first family in web's font stack that the app has
registered and falls back to the system font in the stack's design, with Dynamic Type intact
(`Tests/OuroHXTests/OuroFontTests.swift`):

```swift
Text("Tonight").ouroType(.sjTypeEyebrow)          // font, tracking and line height, scaled with text size
Text("Roast chicken").font(.ouro(type, in: theme.extras))  // the font alone
let brass = theme.extras.color(.sjBrass, scheme)   // nil in a theme without it
```

Bundle the fonts in the app (`UIAppFonts` on iOS, `ATSApplicationFontsPath` on macOS); OuroHX ships none.

The linter exits 0 when all is well, 1 when it trips over itself, 2 for a usage mistake and 3 when it found something.
`--json` gives agents the same facts; `--strict` counts warnings too.

## Ouro Feel: how it feels, measured

Jank comes in genres, and each one now has a check that never gets tired: the way back, overlay dismissal, inside the
window, tap landing, double-draw, jump after landing, late or lingering chrome, snap with no transition, settle time,
place stability, flicker, place kept through stray input and navigation that fights you. Link `OuroFeel` into your UI tests, walk every screen your entry points reach, and leave only real taste to the humans.

```swift
let feel = OuroFeel(app)
feel.expect(feel.wayBack(from: [.launch]))   // every reachable screen has a way back and a gesture back
feel.expect(feel.insideWindow())             // portrait, landscape, portrait again
```

The guide is [docs/ouro-feel/README.md](docs/ouro-feel/README.md); what still needs a human eye is
[docs/ouro-feel/taste-rubric.md](docs/ouro-feel/taste-rubric.md). `Examples/OuroFeelFixture` proves each check catches
its bug.

## Ouro Reins: hand an agent the reins

An agent sees each screen as state and actions and drives it with `ls` and `do`: headless, from fixtures, with the
network blocked. Spoonjoy's Kitchen-to-cook-mode journey takes about 19 ms this way and about 17 s through XCUITest
(Spoonjoy's spike, `spike/w13-reins`).

```sh
swift run ouro-reins-sample ls 'do openItem {"id":"flour"}' 'do toggleStocked' 'do goBack'
```

The guide is [docs/ouro-reins/README.md](docs/ouro-reins/README.md), the agent skill
[docs/ouro-reins/SKILL.md](docs/ouro-reins/SKILL.md), and the decisions
[docs/decisions/2026-11-05-ouro-reins.md](docs/decisions/2026-11-05-ouro-reins.md).

## Agent-composed UI (A2UI)

`ComposedSurface` draws Ouro's composed tree, the format-neutral tree core's adapters resolve to, and calls `onPress`
with a `PersonPress` (the action, the prepared input and that the person pressed it). `A2UISurface` is its A2UI entry
point: it only wraps each press in A2UI's `action` message. Another format's entry point would be one more thin view.

An agent writes A2UI v1.0 messages against your app's catalog (core's `ouro-a2ui-catalog.mts` generates it from your
action set); `OuroA2UI` checks and draws them with Ouro HX. Buttons are your declared actions only: read and write send
A2UI's `action` at once, consequential opens an `.ouroSheet` with what the agent prepared and sends only when the
person confirms, and person-only calls `onHandoff` with the declaration's `how` and never sends one.

```swift
switch A2UI.resolveSurfaces(messages, catalog: try A2UICatalog(data: catalogJSON)) {
case .success(let surfaces):
    if let surface = surfaces.first {
        A2UISurface(surface) { action in agent.send(action) } onHandoff: { action, _ in router.open(action) }
    }
case .failure(let p):
    agent.reply(p.problems.map(\.json))   // A2UI's validation error format, so the agent can correct itself
}
```

A `TextField`, `Checkbox` or `Select` lets the person answer: it starts with what the surface's data model holds at its
`value`, a JSON pointer, and writes their answer there. The surface keeps the data model, and a button whose input is
bound to that pointer sends what they entered, in the confirm sheet and in the press (`ComposedTree.resolveButton`,
`PersonPress.of(_:confirmed:data:)`). They draw with `OuroTextField`, `OuroCheckbox` and, for one choice from a short
list, `OuroSegmentedControl`.

A tree that didn't come as A2UI, such as an MCP tool result's `structuredContent.ouro` or your own code's, goes
through `ComposedTree`, which reads it and checks it against your catalog (core's `validateTree`) before
`ComposedSurface` draws it:

```swift
let tree = try ComposedTree(ouro: result["structuredContent"]?["ouro"] ?? .null, catalog: catalog)
ComposedSurface(tree) { press in callTool(press.action, press.input) } onHandoff: { action, _ in router.open(action) }
```

To change a card it already showed, an agent sends only what changed: an MCP result's `structuredContent.ouro.update`,
`{ nodes?, data? }`. Each node replaces the tree's one node with its id, and each `{ path, value }` sets the data model at
a JSON pointer, `null` deleting it. `ComposedTree.applying(_:catalog:)` applies it all or nothing (core's
`applyTreeUpdate`). `ComposedSurface(results:catalog:)` takes each result's `structuredContent.ouro` in order and shows a
short alert when the newest doesn't apply. What the person entered stays, except where the update changed that value or
the list item it is in.

`Tests/OuroA2UITests` runs core's 13 conformance cases and 5 tree update cases (vendored from ouro-ui-core v0.19.0 and
pinned in `core-provenance.json`'s `tree`); each must give core's tree or problems byte for byte, and they are the same cases
web's `a2ui-surface` passes. The decisions are core's
[2026-11-13-a2ui-catalog.md](https://github.com/ourostack/ouro-ui-core/blob/main/docs/decisions/2026-11-13-a2ui-catalog.md),
[2026-11-14-composed-ui-own-tree.md](https://github.com/ourostack/ouro-ui-core/blob/main/docs/decisions/2026-11-14-composed-ui-own-tree.md),
[2026-11-17-composed-fields.md](https://github.com/ourostack/ouro-ui-core/blob/main/docs/decisions/2026-11-17-composed-fields.md)
and [2026-11-18-composed-tree-updates.md](https://github.com/ourostack/ouro-ui-core/blob/main/docs/decisions/2026-11-18-composed-tree-updates.md).

## The gallery

`Examples/OuroHXGallery` shows every token of every theme in light, dark and increased contrast, and every component
on a page of its own. Its UI tests (`OuroHXGalleryUITests`) prove the component claims on the running app:
`performAccessibilityAudit` on each component page at the default and the largest accessibility text size, in light and
dark, plus 44-point frames, VoiceOver names and the close controls.

Each component's page is one file in `Sources/Pages/` and its claims are one file in `UITests/Pages/`; each registers
itself, so a new component adds two files and edits no shared list. `python3 -I scripts/ui-shards.py check` fails when
a page has one and not the other.

```sh
cd Examples/OuroHXGallery && xcodegen generate && cd ../..
xcodebuild build -project Examples/OuroHXGallery/OuroHXGallery.xcodeproj -scheme OuroHXGallery \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/gallery CODE_SIGNING_ALLOWED=NO
sh scripts/gallery-captures.sh <a simulator UDID you created for it> .build/captures
xcodebuild test -project Examples/OuroHXGallery/OuroHXGallery.xcodeproj -scheme OuroHXGallery \
  -destination 'id=<that UDID>' -derivedDataPath .build/gallery
```

A deeper pass runs by hand, not on pushes: `gh workflow run accessibility-pass.yml` (`.github/workflows/accessibility-pass.yml`).
It runs the same audit with the simulator's own text size set by `simctl ui` to each size from AX1 to AX5, with and
without Increase Contrast, two runners at a time. It also has VoiceOver read every page of the gallery's macOS build (the
`OuroHXGalleryMac` scheme) through Guidepup on a throwaway `macos-15` runner, and lists what a VoiceOver user would
trip on in the job summary (`scripts/voiceover-pass/walk.mjs`). Its inputs narrow the sizes and contrast, or turn the
VoiceOver walk off. A run that only a broken simulator service stopped (#74) is rerun on fresh runners, as CI is.

Component snapshot references live in `Tests/OuroHXTests/__Snapshots__/macOS-<major>`, one folder per host macOS
major. Record locally with `OURO_SNAPSHOT_RECORD=1 swift test --filter ComponentSnapshotTests`; for CI's macOS 26,
take the `snapshots-actual-macos-26` artifact of a failed run.

## X-ray your app's App Intents

Siri reads your intents, entities and app skills the way a coding agent reads a CLI, so they get an X-ray too. It
checks the thirty claims in core's [Ouro AX for Apple standard](https://github.com/ourostack/ouro-ui-core/blob/main/standard/ax/surfaces/apple.md),
from outside the app, and never imports its code:

```sh
swift run ouro-ax-xray --app path/to/App.app --commit "$(git rev-parse --short HEAD)" --out report
```

That reads the app's compiled App Intents metadata and lints its skills bundle, which needs no device. To check how
its queries, Spotlight index, onscreen annotations and errors behave, run the behaviour stage too: it needs a test
bundle (AppIntentsTesting runs only there) and an Xcode whose AppIntentsTesting matches the OS it runs on.
`scripts/xray-probe.sh` makes a simulator, runs [Templates/XrayProbe](Templates/XrayProbe) and merges the result.
If your app indexes its content on its first launch, have it write a file in its data container when that is done,
and pass the file's path with `--ready-file` (the fixture writes `Documents/ouro-ax-ready`), so a slow machine never
probes the index before it has been given anything.
The report says what each lane proved, and that none of it proves what Siri will do; for that, write a Siri scenario
set ([Examples/SiriScenarios](Examples/SiriScenarios)) and run its generated tests on a 27.3 beta device. The whys
are in [docs/decisions/2026-11-03-ax-xray.md](docs/decisions/2026-11-03-ax-xray.md).

## Siri AI

The Siri AI Developer Preview needs the Xcode 27.3 beta SDK. Until you build with it, these compile to nothing:

- `OuroAXToolIntent` (`Sources/OuroAX/AppIntentsSupport.swift`), behind `OURO_SIRI_AI_SDK` or AppIntents newer than 301.1.
- `OuroAXTesting.Wordings.scenarios(_:)` (`Sources/OuroAXTesting/SiriEvaluations+Ouro.swift`), behind
  `canImport(SiriEvaluations)`.
- The Siri scenario tests `ouro-ax-xray scenarios --swift` writes, behind `canImport(SiriEvaluations)`.

CI's `siri-ai-sdk` job compiles them as soon as its image has Xcode 27.3.

## Source stability

Ouro UI for Apple follows [semantic versioning](https://semver.org), on
[swift-argument-parser's model](https://github.com/apple/swift-argument-parser#project-status). The public API is
every public declaration, not starting with an underscore, in the library products (`OuroHX`, `OuroHXTesting`,
`OuroAX`, `OuroAXTesting`, `OuroAXTestingProbe`, `OuroFeel`, `OuroFeelCore`, `OuroFeelRecorder`, `OuroReins`,
`OuroA2UI`). From 1.0.0, a change that breaks a caller's source waits for 2.0; a minor release may add API, deprecate
it, or raise the toolchain it needs. Not covered: the executables' output, the gallery, snapshots and what the
components look like, which follow the design and may change in any release.

Every pull request runs `scripts/api-break.sh`, which compares the API with the last release tag through
[`swift package diagnose-api-breaking-changes`](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/Package/PackageDiagnoseAPIBreakingChange.md).
From 0.9.0 a break fails it, unless the pull request's title starts `Breaking:`; before that it is reported in the
run's summary.

## CI

- **Free GitHub-hosted runners** (`ubuntu-latest`, `macos-26`) run on every pull request and push: core provenance, `swift build` and `swift test`, the skills linter, the iOS Simulator build, DocC and the gallery. The README's first screen is built as a new app from this README, for the Mac and the iOS Simulator, when the README, `OuroHX` or the workflow changes and on every push (`scripts/readme-app.sh`). The gallery's UI tests run on an iPhone on pull requests, and on an iPhone and a 13-inch iPad on `main` and releases. When a change touches Ouro Feel or its fixture, the fixture's tests run in three shards on an iPhone, and its clock-blanking tests run on an iPad, where the iPhone fixture runs in compatibility mode. A shard whose runner has a broken simulator service stops within about a minute and runs again on a fresh runner. Their Xcode 26 has no iOS 27 SDK, so the hinge APIs, AppIntentsTesting and the Siri AI parts compile out behind SDK checks (`#if canImport(SwiftUICore, _version: 8.0.85)` and `canImport`), never compiler checks: Xcode 27.0 and 27.1 have Swift 6.4 but older SDKs.
- **The billed `xcode-27` runner** runs only what needs Xcode 27 or an iOS 27 OS: the Xcode 27 build and test, builds with Xcode 27.0's and 27.1's older SDKs (which also print each SDK's SwiftUICore version), the fixture X-ray lanes, the Siri AI compile lane, and the gallery's fold tests on a folded iPhone Duo simulator (`gallery-duo`). These run on pushes to `main` and on published releases. The one exception is the X-ray lanes, which also run on a pull request that changes the X-ray, Ouro Feel, their fixtures or the workflow, so a break is caught before merge. `xray-apps.yml` runs on releases only. `ios27-claims.yml` runs the component claims on iOS 27 when dispatched for a release candidate (RELEASING.md). Its spending is capped by a $15-a-month Actions budget on this repository, and usage stops at the cap.
- **When the free image ships Xcode 27,** drop the lane: point those jobs at `macos-26` (or `macos-latest`), delete their `if:` gates, and remove this paragraph.
- No self-hosted runners.

## Apps run Ouro Feel

Every app built with Ouro UI links `OuroFeel` into its UI tests and runs a Feel walk of every primary screen, in every
device posture it supports, in CI ([the guide](docs/ouro-feel/README.md#every-app-runs-it)). A jank report from a
person is first a missing check: write the check that would have caught it, see it fail, then fix the app.

## Working on it

Read [AGENTS.md](AGENTS.md): where core lives, how a token bump works, and why names match web. Decisions are in
[docs/decisions](docs/decisions). Credit where it's due: most of this grew up in
[Spoonjoy](https://github.com/spoonjoy/spoonjoy-apple) and [Gatefold](https://github.com/ourostack/gatefold) first.

MIT, © 2026 Ari Mendelow.
