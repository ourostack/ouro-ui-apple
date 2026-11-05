# 2026-11-05: Ouro Reins, agents drive an app's screens as state and actions

Status: accepted (W13 of the HX and AX native program).

## Context

Agents drive Ouro UI apps through XCUITest: a booted simulator, screenshots and accessibility labels, about 17 s for
Spoonjoy's Kitchen-to-cook-mode journey before launch. Live journeys also fail on dropped connections. Shopify's
[Reflex](https://shopify.engineering/reflex) showed the alternative: view models exposed as nodes of state and
actions, driven headless with `ls` and `do`, with the network blocked. Ari sent it on 2026-11-05: "relevant to
ouro!!!!! yours to do with as you please :)".

## Decision

1. **One library, `OuroReins`, here.** It depends only on `OuroAX` (for `OuroAX.Problem`) and never imports SwiftUI
   or XCTest, so an app's UI-free core links it.
2. **Nodes are values rebuilt on every `ls`.** `{name, state, actions, lends, child}`; the focus is the deepest node.
   No retained tree, so nothing to keep in sync with the app.
3. **Containers lend actions.** `stack` lends `goBack` below its root, `tabs` lends `selectTab`; the nearest lender
   wins. A full-screen cover replaces what it covers in the tree.
4. **Refuse before running.** An unavailable action or input that fails its schema never reaches app code; the reply
   is an `OuroAX.Problem` naming the valid actions or the wrong JSON path. Exits: 0 ok, 2 refused, 1 the action
   threw, 3 the network was attempted.
5. **Schemas from `Decodable`, no macro.** A recording decoder derives the JSON Schema; `ReinsEnumerable` gives
   `oneOf`; a type whose decoder validates declares `reinsSchema`, and until it does its action refuses every input
   with that fix. `narrowed(_:)` limits a schema to the values on screen.
6. **NDJSON, three ways.** Text or JSON lines through `ReinsCommandLine` (arguments or stdin), the same lines over a
   Unix domain socket in debug builds (`ReinsSocketServer`, under `#if DEBUG`, proven absent from release objects by
   `scripts/check-reins-release.sh` in CI), and `ReinsSession`/`ReinsJourney` in tests.
7. **The network is blocked and checked.** `ReinsNetworkGuard` blocks `URLSession.shared` and every session made from
   `.default` or `.ephemeral` while it runs, records each attempt, and `check()` fails the test even when the app
   recovered. Its gaps (pre-made configurations, background sessions, Network.framework, sockets, WebKit) are
   documented; fixtures come through constructors.
8. **Names.** Public types are `Reins*` in `OuroReins`, as Ouro Feel's are `Feel*`. AGENTS.md's naming rule now names
   that kit-prefix pattern, since two kits follow it.

Spoonjoy's spike (`spike/w13-reins` on spoonjoy-apple) drove its real `NativeLiveAppStore` and view models from the
screenshot fixture kitchen, with no change to SpoonjoyCore: 18.7 ms median per journey headless against 16.7 s in
XCUITest, zero network attempts, and a live-first control that the guard caught
(`GET https://spoonjoy.app/api/v1/me/sync?limit=20`). It also found that `withNetworkBlocked` couldn't take a
`@MainActor` closure under Swift 6; it now inherits the caller's isolation.

An independent review before merge found four blockers, all fixed with regression tests
(`Tests/OuroReinsTests/ReinsReviewRegressionTests.swift`): the default socket path was too long for a simulator app
(now `OURO_REINS_SOCKET` or a short `/tmp` path), a client hanging up early killed the app with SIGPIPE, the guard
spun on the main thread and deadlocked parallel `@MainActor` tests (it now suspends), and a recursive input type
recursed forever (now underived with a reason). Its should-fix findings were fixed too: non-finite numbers, ids on
parse failures, nested navigator names, exit 3 on the command line, `file:` URLs under the guard, dictionary and
`Decimal`/`Data` schemas with formats, serial socket requests and `\n`-only line splitting.

## Not decided here

- A claims-standard field so the X-ray checks an intent's claim against node state: a core change first.
- Ouro Feel reading the focus over the debug socket: to prove in Spoonjoy's adoption.
- An MCP face, a `routes` op, screen hashes and `--diff`: fast-follows.

## Prior art

| Prior art | Disposition |
|---|---|
| [Shopify Reflex](https://shopify.engineering/reflex) | adopt: the contract, minus its macro and Kotlin parity |
| [TCA](https://github.com/pointfreeco/swift-composable-architecture) | borrow: exhaustive assertions and diffs; not the framework |
| [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) | borrow: a live dependency in a test is a failure |
| [swift-custom-dump](https://github.com/pointfreeco/swift-custom-dump) | borrow: diffs for journey failures (fast-follow) |
| [swift-navigation](https://github.com/pointfreeco/swift-navigation), [swift-issue-reporting](https://github.com/pointfreeco/swift-issue-reporting) | watch |
| [Square Workflow](https://github.com/square/workflow-swift) | borrow: renderings as a value tree, tested without UI |
| [Uber DragonCrawl](https://www.uber.com/en-US/blog/generative-ai-for-high-quality-mobile-testing/) | borrow: refusals that teach the agent loop |
| [XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP) | adopt as the build-and-run layer; borrow screen hash and batching |
| [Callstack agent-device](https://github.com/callstackincubator/agent-device) | borrow: refs and `--diff` |
| [Maestro MCP](https://docs.maestro.dev/mcp) | borrow: its cheat sheet became `help` |
| [mobile-mcp](https://github.com/mobile-next/mobile-mcp), [Arbigent](https://github.com/takahirom/arbigent), [AXe](https://github.com/cameroncooke/AXe) | watch: outside-in drivers |
| [Appium MCP](https://github.com/appium/appium-mcp), [KIF](https://github.com/kif-framework/KIF), [ViewInspector](https://github.com/nalexn/ViewInspector), [idb](https://github.com/facebook/idb) | ignore: they drive views, the layer Reins skips |
| [Dart MCP server](https://github.com/dart-lang/ai/tree/main/pkgs/dart_mcp_server), [Expo MCP](https://docs.expo.dev/eas/ai/mcp/), [Playwright MCP](https://github.com/microsoft/playwright-mcp) | borrow: tree-as-tools, a router sitemap, snapshot depth and refs |
| [EarlGrey 2](https://github.com/google/EarlGrey/tree/earlgrey2) | borrow: wait for idle (`settle`) |
| [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | borrow: golden `ls` JSON |
| [AppIntentsTesting (WWDC26 295)](https://developer.apple.com/videos/play/wwdc2026/295/) | adopt for the X-ray bridge |
| [Elm's perfect bug report](https://elm-lang.org/news/the-perfect-bug-report), [Redux DevTools](https://github.com/reduxjs/redux-devtools) | borrow: the replayable transcript |
| [Compose semantics](https://developer.android.com/develop/ui/compose/testing/semantics) | watch |
| [swift-json-schema](https://github.com/ajevans99/swift-json-schema) | watch: macro schemas, pre-1.0, adds swift-syntax |
| [MCP swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) | adopt later, in its own target |
| [OHHTTPStubs](https://github.com/AliSoftware/OHHTTPStubs), [Mocker](https://github.com/WeTransfer/Mocker) | borrow: global protocol plus swizzled default configurations |

The full meerkat pass is in the program's desk notes.
