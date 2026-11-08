# Ouro Reins

Ouro Reins hands an agent the reins of an Ouro UI app: it sees each screen as state and actions, and drives it with
`ls` and `do`, headless, in milliseconds, with the network blocked. No simulator, no screenshots, no tapping by
coordinates. The idea is Shopify's [Reflex](https://shopify.engineering/reflex); the decisions are in
[docs/decisions/2026-11-05-ouro-reins.md](../decisions/2026-11-05-ouro-reins.md).

- **`OuroReins`** (link it into your app's UI-free core, its tests or a small executable) has no SwiftUI and no
  XCTest. It holds the node tree, the session, the wire protocol, the network guard, journeys and the debug socket.
- **`ouro-reins-sample`** is a small pantry app driven the same way; CI runs it as an agent would.

Where it sits beside the other Ouro tools: the [Ouro AX X-ray](../decisions/2026-11-03-ax-xray.md) checks what the app
claims to the system (App Intents, accessibility), [Ouro Feel](../ouro-feel/README.md) checks how it feels in the
simulator, and Reins drives its behaviour without either.

## The model

A screen is a tree of **nodes**. Each node has a `name`, its `state` as JSON, the `actions` it offers (each with an
input JSON Schema) and at most one `child`. The deepest node is the **focus**: the screen in front of you.

- `ls` returns the focus, its path from the root, its state, its ancestors' states as `context`, and every action
  you may run now.
- `do <action> [json]` runs one. An action that isn't offered is **refused** before anything runs, with the actions
  that are: `goBack isn't available on kitchen. Fix: use one of: openRecipe, startCooking, selectTab.` Input that
  doesn't match the schema is refused with the path that's wrong (`$.id: "recipe_nope" isn't one of "recipe_pasta", ...`).
- Containers **lend** actions to whatever is focused inside them: a navigation stack lends `goBack` once it is deeper
  than its root, a tab bar lends `selectTab`. The nearest lender wins when two lend the same name.
- An action's schema can be **narrowed** to the values valid right now (`selectTab` to the tabs that exist,
  `openRecipe` to the recipes on screen), so `ls` shows exactly what will be accepted.

## Make an app drivable

You don't rewrite your view models. You add one object that builds the tree from what you already have:

```swift
import OuroReins

struct RecipeID: ReinsInput { let id: String }   // its JSON Schema is derived from Decodable

@MainActor
final class Shell: ReinsDrivable {
    let store: AppStore
    var path: [Route] = []

    var reinsNode: ReinsNode {
        .tabs(selected: "kitchen", tabs: ["kitchen", "shopping"], select: { self.select($0) }, child:
            .stack(depth: path.count, goBack: { self.path.removeLast() }, child: page))
    }

    private var page: ReinsNode {
        ReinsNode("kitchen", encoding: store.kitchen, actions: [
            ReinsAction("openRecipe", "Open a recipe", input: RecipeID.self) { self.path.append(.recipe($0.id)) }
                .narrowed(.object(properties: ["id": .oneOf(store.recipeIDs)], required: ["id"])),
        ])
    }
}
```

- **State** is any `Encodable` (`ReinsNode(_:encoding:)`) or a `ReinsValue` literal. Encode what a person reads on
  the screen, not your whole model.
- **Availability comes from the model, not the node.** When an action exists only sometimes (a next step, a recipe
  list that isn't empty), read the same view-model property the view uses to show or enable the control. A condition
  written only in the node can disagree with the screen.
- **Inputs** are `Decodable` structs that conform to `ReinsInput`; the schema is derived by decoding a placeholder.
  String enums conform to `ReinsEnumerable` to become `oneOf`. When derivation can't work (custom `init(from:)` that
  validates), declare `static var reinsSchema` yourself; until you do, the action refuses every input and says why.
- **The glue goes in core.** Whatever a SwiftUI binding does on a tap (push a route, dismiss a cover, turn a page)
  belongs in a model both the view and Reins call. If it lives in the view today, moving it is the adoption cost.

## Drive it

Headless, from a test or an agent, against fixtures passed through constructors:

```swift
try await ReinsNetworkGuard.withNetworkBlocked {
    let session = ReinsSession(Shell(store: .fixtureKitchen()))
    let journey = ReinsJourney(session)
    try await journey.do("openRecipe", ["id": "recipe_pasta"], until: { $0.focus == "recipe" })
    try await journey.do("goBack", until: { $0.focus == "kitchen" })
}
```

A journey step polls until its condition holds (2 s by default) and otherwise fails with what it waited for, the last
screen as JSON and the `do` lines to replay it.

From a shell, an executable calls `ReinsCommandLine.run { ... }`, building the session inside the closure so the network
guard is already up when the app's stores and URL sessions are made:

```swift
await ReinsCommandLine.run(settle: .seconds(1)) { ReinsSession(Shell(store: try .fixtureKitchen())) }
```

Arguments are lines; with none it reads stdin, split at `\n` only. One JSON reply per line:

```sh
swift run my-app-reins ls 'do openRecipe {"id":"recipe_pasta"}' 'do goBack'
printf '{"id":1,"op":"ls"}\n{"id":2,"op":"do","action":"goBack"}\n' | swift run my-app-reins
```

Exit codes: 0 every line succeeded, 2 something was refused, 1 an action failed, 3 something tried to reach the network
(listed on stderr). `settle` waits after the last line so a debounced save or sync is caught too. `help` prints the
protocol.

In a running debug build, `ReinsSocketServer` serves the same lines on a Unix socket. Its path is `OURO_REINS_SOCKET`
when the launch environment sets it, else `ouro-reins.sock` in the app's temporary folder, or
`/tmp/ouro-reins-<bundle id>-<simulator UDID>.sock` when that's too long for a socket address (a simulator app's
usually is), so two simulators running the same app don't collide; `start()` prints it on stderr and refuses to take
over a socket another server is still answering on. Requests from all connections run one at a time. Wrap your own calls in `#if DEBUG`: the type
doesn't exist in release builds, which `scripts/check-reins-release.sh` proves in CI for `swift build -c release`.

```swift
#if DEBUG
try? ReinsSocketServer(session: ReinsSession(shell)).start()
#endif
```

```sh
printf 'ls\n' | nc -U "/tmp/ouro-reins-app.spoonjoy-$UDID.sock"
```

## The network guard

`ReinsNetworkGuard.begin()` (or `withNetworkBlocked`) fails every URL load through `URLSession.shared` and every
session made from `.default` or `.ephemeral` configurations created while it runs, and records each as
`GET https://...`. `check()` throws `network-attempted` (exit 3) listing them, so a test fails even when the app
recovered from the error. `ReinsNetworkGuard.blocking()` gives a configuration that always fails, for sessions you
build yourself.

Only `http`, `https`, `ws` and `wss` are blocked, so bundled fixtures load through `file:` URLs. One guard is active at
a time; `begin()` suspends until the previous one ends, so parallel tests take turns.

It does **not** see sessions created before `begin()` from a configuration captured earlier, background sessions,
Network.framework, raw sockets or WebKit. Inject those dependencies; don't rely on the guard to find them. A session
created while a guard was active keeps failing network requests after `end()`, unrecorded, so build sessions inside
the guard that checks them.

## Known gaps

- One child per node, so a split view whose sidebar and detail are both live shows only the focused column (Reflex
  has the same limit). Model the sidebar's choices as actions on the detail's parent until this matters.
- Nested navigators with the same name appear as `stack`, `stack.2` and so on in `path`, `context` and `from`; give
  them distinct names when an agent needs to tell them apart.
- The same suffix applies to `focus`: a focused node named like one of its ancestors reads `page.2`, so
  `journey.expect("page")` won't match it and Ouro Feel's screen identity depends on the ancestors. Give the focused
  screen a name no ancestor uses.

## The protocol

[PROTOCOL.md](PROTOCOL.md) is the wire contract on its own, independent of this Swift code: the screen, the requests and replies, every refusal code with its exit, journeys, and the optional batches and diffs a remote driver uses. Write another driver against it, and change it (and its Changes list) in the same pull request as any wire change here.

## Reins for any Mac app

The same `ls` and `do`, for every app on a Mac, not only Ouro UI apps: an agent drives Finder, System Settings or a vendor's app as state and actions, with no model in the loop and no clicking by coordinates. It's a second driver, for Ari's own Macs, that now speaks [PROTOCOL.md](PROTOCOL.md) (it also sends `available` and `path` as fields); the code isn't public yet.

- **The accessibility layer.** A resident engine reads the front app's accessibility tree (or a named app's) and prunes it to what a person can act on: each element has a role, a label, its value, whether it's enabled or focused, and its frame. Blocking alerts come first. Actions are narrowed to the screen: `click`'s `element` is an `enum` of the elements that can be clicked, `menu`'s `item` of the menu-bar items that are enabled (`File > New Finder Window`), `open_app`'s `app` of the installed apps. The others are `set_value`, `type_text`, `press_key` (`cmd+w`), `scroll`, `perform` (any other accessibility action) and `activate`.
- **Stable addresses.** Each element has `#12`, its index on this screen, and a ref like `button[Back]` or `toolbar > button[Back]`: the shortest role-and-label path that's unique on the screen. An editable field is never named by its own value. A recorded journey keeps refs; on replay, a ref that no longer matches exactly matches by a unique suffix of the element's full path.
- **The pixel layer.** Where there's no usable tree (FileVault and the login window, a canvas, a hung window server, or a Mac that hasn't granted Accessibility), the same screen comes from a screenshot: Apple Vision's text boxes become `text[Label]` elements, `"layer": "pixels"` says so, and clicks, keys and text go through a pixel driver. One driver is an IP-KVM (a GL.iNet Comet, through PiKVM's HTTP API), whose HDMI capture and USB keyboard and mouse need no permission on the Mac at all.
- **Safe by refusal.** It refuses with `person-active` when anyone has touched the Mac in the last 90 seconds, `app-protected` for apps whose own policy refuses automation (the GitHub Copilot app, which has its own local API), password and administrator prompts, consents its own tools didn't raise, and device-management or security settings, and `permission-missing` when Accessibility hasn't been granted. It never raises a permission prompt on a screen nobody is at, never types a password given on a command line, and reads a secret only from the Mac's Keychain by name.
- **Fast across a network.** The driver runs on the Mac and only lines cross the network, so the engine stays resident and warm, `batch` runs a whole journey in one round trip with every `until` checked on the Mac, and after the first screen only a diff against the `rev` the agent holds comes back.

## Agent skill

[SKILL.md](SKILL.md) is the short version for an agent that has to drive an app it didn't write.
