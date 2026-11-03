# 2026-11-03: the shape of ouro-ui-apple

Status: accepted (W3 of the HX and AX native program).

## Decision

1. **One SwiftPM package at the repository root**, `OuroUIApple`, with four libraries (`OuroHX`, `OuroHXTesting`,
   `OuroAX`, `OuroAXTesting`), two executables (`ouro-ax-skills`, `ouro-devicehub`) and one build-tool plugin
   (`OuroAXSkillsLintPlugin`). An app takes only the products it imports; the testing products go in test targets.
2. **The floor is iOS 18 and macOS 15**, Swift 6 language mode, tools version 6.1 (the plugin needs
   `SourceModuleTarget.directoryURL`). iOS 27.1's hinge and reserved regions sit behind `#available`.
3. **Tokens are vendored, not depended on.** `OuroTokens.swift` is core v0.1.0's release asset, byte for byte;
   `core-provenance.json` pins its SHA-256 and CI compares the file, the pin, core's `dist-manifest.json` and the
   downloaded asset. A SwiftPM dependency on core would pull a Node repository into every app's resolve.
4. **Increased contrast is derived until core has tokens for it.** `OuroColor.increasedContrast(_:)` raises text to 7:1
   and lines to 3:1; tests check every theme in both schemes. When core ships high-contrast tokens, this follows core.
5. **`OuroTokens.Duration` keeps its name.** It mirrors core's `ouro.duration` group, as `Ease`, `Spring` and `Press`
   mirror theirs, and web and core name it the same. It shadows `Swift.Duration` only inside `OuroTokens`'s own scope,
   which this package never extends; code here that needs the standard type writes `Swift.Duration`. No rename PR to
   core.
6. **Siri AI Developer Preview code compiles out on Xcode 27.2.** Tool-intent code sits behind
   `#if OURO_SIRI_AI_SDK || canImport(AppIntents, _version: 301.2)` (27.2's AppIntents is 301.1.16) and SiriEvaluations
   code behind `#if canImport(SiriEvaluations)`. CI's `siri-ai-sdk` lane compiles both once the runner image carries
   Xcode 27.3.
7. **CI runs on GitHub's `xcode-27` image**, the label Gatefold and Spoonjoy use; `macos-26` carries Xcode 26 only.
8. **`ouro-devicehub` keeps the apps' `dump` and `press` output and exit codes** (0, 1 no process, 2 not found, 3 not
   trusted, 4 press failed), so Gatefold's and Spoonjoy's workflows switch by changing one path. Two changes: an
   unknown command or a missing argument exits 64 (the original ran `dump` or crashed), and `serve <dir>` is new, the
   Mac side of the Duo request files.
9. **The skills linter speaks ax-problem.** JSON is `skills-lint/1`; findings are problems whose `exit` is 3 for an error and 0 for a warning (3 under `--strict`); usage errors
   exit 2 with `{"error": …}`; warnings count only under `--strict`.

## Prior art

| Find | What it does | Verdict |
|---|---|---|
| [microsoft/fluentui-apple](https://github.com/microsoft/fluentui-apple) | One package, per-platform targets (`FluentUI_ios`, `FluentUI_macos`) over a common one, with a token layer | **Borrow** the one-package, products-by-need shape; **ignore** split per-platform targets, since SwiftUI covers both |
| [Skyscanner/backpack-ios](https://github.com/Skyscanner/backpack-ios) | Design system with tokens generated from a shared source | **Borrow** "tokens are generated, never hand-edited" (already core's rule) |
| [style-dictionary](https://github.com/style-dictionary/style-dictionary) | Cross-platform token build | **Watch**; core's own generator already writes the Swift |
| [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | Snapshot testing with strategies and recording | **Watch**; `OuroSnapshot` is a small `ImageRenderer` helper with no dependency, and apps that want more can use this instead |
| [uber/ios-snapshot-test-case](https://github.com/uber/ios-snapshot-test-case) | UIKit snapshot testing | **Ignore**: UIKit-era |
| [nalexn/ViewInspector](https://github.com/nalexn/ViewInspector) | SwiftUI view-tree introspection | **Ignore** for now: our checks are pure functions plus renders |
| [Cocoanetics/SwiftMCP](https://github.com/Cocoanetics/SwiftMCP) | MCP servers in Swift | **Watch** for Ouro MD's Mac door; SiriEvaluations replaced it for evaluating Siri |
| [Agent Skills](https://agentskills.io) and Apple's [app skills guide](https://developer.apple.com/documentation/appintents/orchestrating-complex-actions-with-app-skills) | The skill format and Apple's subset of it | **Adopt** Apple's rules as the linter's errors |
| Spoonjoy and Gatefold (ours) | The motion, haptic, contrast, fold and Duo code this package generalizes | **Adopt**, credited in each DocC article |

## Consequences

- Apps adopt by adding the package and deleting their copies, one piece at a time, through their own PRs.
- A token bump is a PR here that names the core tag (see `AGENTS.md`).
- When Xcode 27.3 reaches the runner image, the Siri lane starts compiling the guarded code with no change here.
