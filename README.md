# Ouro UI for Apple

**Ouro HX for people and Ouro AX for agents, in Swift.** The same colours, motion and manners as
[ui.ouro.bot](https://ui.ouro.bot/), now on iPhone, iPad and Mac, plus the bits that make an app pleasant for Siri and
every other agent that comes knocking.

Meets core [v0.3.0](https://github.com/ourostack/ouro-ui-core/releases/tag/v0.3.0): the tokens and the claim sets (AX's
`apple.claims.json`, HX's `components.claims.json`) are core's, byte for byte, and CI checks it.

## Install

```swift
.package(url: "https://github.com/ourostack/ouro-ui-apple.git", from: "0.3.0")
```

iOS 18 and macOS 15 or later, Swift 6. Newer things (the iPhone Duo's hinge, Siri AI) switch on by themselves where the
OS has them.

## What's in the box

| Product | For | What it has |
|---|---|---|
| `OuroHX` | your app | the components: `OuroButton` (solid, soft, outline, plain, glass; rounded or pill), `OuroEmptyState`, `OuroBanner`, `.ouroSheet`, and toasts (`.ouroToaster()` at the root, then `@Environment(\.ouroToast)`); `.ouroTheme(.pearl)`, `ouroColors` and radii in the environment; `OuroColor` (contrast, increased contrast, adaptive colours); `OuroMotion` (core's spring and curves, polite under Reduce Motion); `OuroHaptics` (one named table of moments); `OuroFoldPosture` and `OuroFoldReader` (tabletop, book, closed) |
| `OuroHXTesting` | your tests | `OuroSnapshot` (light, dark, increased contrast), `ouroAccessibilityAudit`, `OuroDuoHinge` (fold the Duo simulator from a UI test) |
| `OuroAX` | your app | `OuroAX.Outcome` and `OuroAX.Problem` (web's `ax-outcome` and `ax-problem`, field for field), exit codes, entity queries with fuzzy matching, `OuroAXOutcomeIntent`, `OuroAXPackage` |
| `OuroAXTesting` | your tests | Siri evaluation wordings and pass rates; the App Intents X-ray's checks, reports and Siri scenario sets (`AXXray`) |
| `ouro-ax-xray` | you and CI | X-rays a built app's App Intents against Ouro AX for Apple's claims: `swift run ouro-ax-xray --app path/to/App.app --out report` |
| `OuroAXTestingProbe` | the X-ray's test plan | runs the X-ray's behaviour stage with AppIntentsTesting ([Templates/XrayProbe](Templates/XrayProbe)) |
| `ouro-ax-skills` | you and CI | lints `Skills.skillsbundle` for Siri: `swift run ouro-ax-skills lint path/to/Skills.skillsbundle` |
| `OuroAXSkillsLintPlugin` | your build | the same lint at build time, with errors pinned to the line |
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

The linter exits 0 when all is well, 1 when it trips over itself, 2 for a usage mistake and 3 when it found something.
`--json` gives agents the same facts; `--strict` counts warnings too.

## Ouro Feel: how it feels, measured

Jank comes in genres, and each one now has a check that never gets tired: the way back, overlay dismissal, inside the
window, tap landing, double-draw, jump after landing, late or lingering chrome, snap with no transition, settle time
and place stability. Link `OuroFeel` into your UI tests, walk every screen your entry points reach, and leave only real taste to the humans.

```swift
let feel = OuroFeel(app)
feel.expect(feel.wayBack(from: [.launch]))   // every reachable screen has a way back and a gesture back
feel.expect(feel.insideWindow())             // portrait, landscape, portrait again
```

The guide is [docs/ouro-feel/README.md](docs/ouro-feel/README.md); what still needs a human eye is
[docs/ouro-feel/taste-rubric.md](docs/ouro-feel/taste-rubric.md). `Examples/OuroFeelFixture` proves each check catches
its bug.

## The gallery

`Examples/OuroHXGallery` shows every token of every theme in light, dark and increased contrast, and every component
(the Buttons, Empty states, Banners, Sheets and Toasts pages). Its UI tests (`OuroHXGalleryUITests`) prove the
component claims on the running app: `performAccessibilityAudit` on each component page at the default and the largest
accessibility text size, in light and dark, plus 44-point frames, VoiceOver names and the close controls.

```sh
cd Examples/OuroHXGallery && xcodegen generate && cd ../..
xcodebuild build -project Examples/OuroHXGallery/OuroHXGallery.xcodeproj -scheme OuroHXGallery \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/gallery CODE_SIGNING_ALLOWED=NO
sh scripts/gallery-captures.sh <a simulator UDID you created for it> .build/captures
xcodebuild test -project Examples/OuroHXGallery/OuroHXGallery.xcodeproj -scheme OuroHXGallery \
  -destination 'id=<that UDID>' -derivedDataPath .build/gallery
```

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

## CI

- **Free GitHub-hosted runners** (`ubuntu-latest`, `macos-26`) run on every pull request and push: core provenance, `swift build` and `swift test`, the skills linter, the iOS Simulator build, DocC and the gallery. Their Xcode 26 has no iOS 27 SDK, so the hinge APIs, AppIntentsTesting and the Siri AI parts compile out behind SDK checks (`#if canImport(SwiftUICore, _version: 8.0.85)` and `canImport`), never compiler checks: Xcode 27.0 and 27.1 have Swift 6.4 but older SDKs.
- **The billed `xcode-27` runner** runs only what needs Xcode 27 or an iOS 27 OS: the Xcode 27 build and test, builds with Xcode 27.0's and 27.1's older SDKs (which also print each SDK's SwiftUICore version), the fixture X-ray lanes and the Siri AI compile lane. It runs on pushes to `main` and on published releases, never on pull requests; `xray-apps.yml` runs on releases only. Its spending is capped by a $15-a-month Actions budget on this repository, and usage stops at the cap.
- **When the free image ships Xcode 27,** drop the lane: point those jobs at `macos-26` (or `macos-latest`), delete their `if:` gates, and remove this paragraph.
- No self-hosted runners.

## Working on it

Read [AGENTS.md](AGENTS.md): where core lives, how a token bump works, and why names match web. Decisions are in
[docs/decisions](docs/decisions). Credit where it's due: most of this grew up in
[Spoonjoy](https://github.com/spoonjoy/spoonjoy-apple) and [Gatefold](https://github.com/ourostack/gatefold) first.

MIT, © 2026 Ari Mendelow.
