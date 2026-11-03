# Ouro UI for Apple

**Ouro HX for people and Ouro AX for agents, in Swift.** The same colours, motion and manners as
[ui.ouro.bot](https://ui.ouro.bot/), now on iPhone, iPad and Mac, plus the bits that make an app pleasant for Siri and
every other agent that comes knocking.

Meets core [v0.1.0](https://github.com/ourostack/ouro-ui-core/releases/tag/v0.1.0): the tokens are core's, byte for
byte, and CI checks it.

## Install

```swift
.package(url: "https://github.com/ourostack/ouro-ui-apple.git", from: "0.1.0")
```

iOS 18 and macOS 15 or later, Swift 6. Newer things (the iPhone Duo's hinge, Siri AI) switch on by themselves where the
OS has them.

## What's in the box

| Product | For | What it has |
|---|---|---|
| `OuroHX` | your app | `.ouroTheme(.pearl)`, `ouroColors` and radii in the environment; `OuroColor` (contrast, increased contrast, adaptive colours); `OuroMotion` (core's spring and curves, polite under Reduce Motion); `OuroHaptics` (one named table of moments); `OuroFoldPosture` and `OuroFoldReader` (tabletop, book, closed) |
| `OuroHXTesting` | your tests | `OuroSnapshot` (light, dark, increased contrast), `ouroAccessibilityAudit`, `OuroDuoHinge` (fold the Duo simulator from a UI test) |
| `OuroAX` | your app | `OuroAX.Outcome` and `OuroAX.Problem` (web's `ax-outcome` and `ax-problem`, field for field), exit codes, entity queries with fuzzy matching, `OuroAXOutcomeIntent`, `OuroAXPackage` |
| `OuroAXTesting` | your tests | Siri evaluation wordings and pass rates; more in the next release |
| `ouro-ax-skills` | you and CI | lints `Skills.skillsbundle` for Siri: `swift run ouro-ax-skills lint path/to/Skills.skillsbundle` |
| `OuroAXSkillsLintPlugin` | your build | the same lint at build time, with errors pinned to the line |
| `ouro-devicehub` | a Mac CI job | presses Device Hub's buttons: `dump`, `press "Partially Open"`, `serve <dir>` |

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

// At the root:
ContentView().ouroTheme(.pearl)
```

The linter exits 0 when all is well, 1 when it trips over itself, 2 for a usage mistake and 3 when it found something.
`--json` gives agents the same facts; `--strict` counts warnings too.

## The gallery

`Examples/OuroHXGallery` shows every token of every theme in light, dark and increased contrast.

```sh
cd Examples/OuroHXGallery && xcodegen generate && cd ../..
xcodebuild build -project Examples/OuroHXGallery/OuroHXGallery.xcodeproj -scheme OuroHXGallery \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/gallery CODE_SIGNING_ALLOWED=NO
sh scripts/gallery-captures.sh <a simulator UDID you created for it> .build/captures
```

## Siri AI

The Siri AI Developer Preview needs the Xcode 27.3 beta SDK. Until you build with it, these compile to nothing:

- `OuroAXToolIntent` (`Sources/OuroAX/AppIntentsSupport.swift`), behind `OURO_SIRI_AI_SDK` or AppIntents newer than 301.1.
- `OuroAXTesting.Wordings.scenarios(_:)` (`Sources/OuroAXTesting/SiriEvaluations+Ouro.swift`), behind
  `canImport(SiriEvaluations)`.

CI's `siri-ai-sdk` job compiles them as soon as its image has Xcode 27.3.

## Working on it

Read [AGENTS.md](AGENTS.md): where core lives, how a token bump works, and why names match web. Decisions are in
[docs/decisions](docs/decisions). Credit where it's due: most of this grew up in
[Spoonjoy](https://github.com/spoonjoy/spoonjoy-apple) and [Gatefold](https://github.com/ourostack/gatefold) first.

MIT, © 2026 Ari Mendelow.
