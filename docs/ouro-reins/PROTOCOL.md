# The Reins protocol, version 1

This is the contract between an agent and anything it drives with Ouro Reins: an Ouro UI app (`OuroReins`, in this package) or a whole Mac (Reins for any Mac app, [below](#implementations)). It says what crosses the wire and nothing about how a driver builds it, so one agent skill drives every implementation. The Swift types are the reference: `ReinsScreen`, `ReinsActionInfo`, `ReinsReply` and `ReinsWire` in `Sources/OuroReins/`, and `OuroAX.Problem` in `Sources/OuroAX/Problem.swift`.

The key words MUST, SHOULD and MAY are used as in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

## 1. The screen

`ls` returns the screen an agent is looking at:

```json
{
  "focus": "recipe",
  "path": ["app", "tabs", "stack", "recipe"],
  "state": { "title": "Pasta", "servings": 2 },
  "context": { "tabs": { "selected": "kitchen" }, "stack": { "depth": 1 } },
  "actions": [
    { "name": "setServings", "title": "Set servings", "from": "recipe",
      "input": { "type": "object", "properties": { "n": { "type": "integer" } }, "required": ["n"], "additionalProperties": false } },
    { "name": "goBack", "title": "Back", "from": "stack" }
  ]
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `focus` | yes | The name of the screen in front of the agent: the deepest node. |
| `path` | yes | Names from the root to the focus. |
| `state` | yes | What a person reads on that screen, as JSON. |
| `context` | yes | The state of each node above the focus, by name (`{}` when there is none). |
| `actions` | yes | Every action the driver accepts **now**. Nothing else exists. |

An action is `{name, title, input?, from}`. `input` is the JSON Schema its input must match, absent when it takes none. `from` names the node that offers it: the focus itself, or an ancestor that lends it (a stack lends `goBack`); when two lend the same name, the nearest wins.

A driver SHOULD **narrow** schemas to the values valid right now (an `enum` of the recipes on screen, of the elements that can be clicked), so `ls` shows exactly what will be accepted.

A driver MAY add top-level fields. One is defined here: `rev` (§7).

## 2. Requests

One request per line, as text or as JSON:

```
ls
do openRecipe {"id":"r1"}
help
{"id":1,"op":"ls"}
{"id":2,"op":"do","action":"openRecipe","input":{"id":"r1"}}
```

- A line starting with `{` MUST be JSON with `op` set to `ls`, `do` or `help`; `do` needs `action` and MAY have `input`. Any `id` (string or number) is echoed in the reply.
- A blank line or one starting with `#` gets no reply.
- Lines are split at `\n` only; a trailing `\r` is dropped.

## 3. Replies

One JSON line per request:

```json
{"id":2,"ok":true,"screen":{ … }}
{"id":3,"ok":false,"error":{"code":"action-unavailable","exit":2,"thing":"do goBack","problem":"goBack isn't available on kitchen","fix":"use one of: openRecipe, selectTab","message":"do goBack: goBack isn't available on kitchen. Fix: use one of: openRecipe, selectTab."},"screen":{ … }}
```

- `ok` is required. `screen` is the screen **after** the request. A refused request leaves the screen as it was and returns it, so the valid actions are always in the reply and an agent rarely needs another `ls`.
- `error` is an Ouro AX problem: `code` (a stable slug to branch on), `exit`, `thing`, `problem`, `fix` (the exact thing to do instead, or null) and `message`: `<thing>: <problem>.`, followed by ` Fix: <fix>.` when `fix` isn't null, with trailing periods and spaces trimmed from each part. A driver MAY add fields to it (§4); OuroReins sends exactly these six.
- `help` replies `ok`, the screen and `help`: the protocol in a few lines, so an agent that finds a socket can learn it from the socket.

## 4. Refusals and failures

A driver MUST check an action against `actions` and its input against the schema **before** anything runs. The codes:

| Code | Exit | When | Where the detail is |
| --- | --- | --- | --- |
| `action-unavailable` | 2 | The action isn't offered on this screen. | `fix` lists the actions that are (`use one of: …`). A driver MAY also send them as `available`, an array. |
| `input-invalid` | 2 | The input doesn't match the schema. | `problem` starts with the JSON path that's wrong (`$.id: …`). A driver MAY also send it as `path`. |
| `input-unexpected` | 2 | Input was sent to an action that takes none. | |
| `bad-request` | 2 | The line isn't a request. | |
| `action-failed` | 1 | The action ran and failed. This is a finding, not something to retry. `fix` is usually null. | |
| `network-attempted` | 3 | Something tried to reach the network under a guard that forbids it (OuroReins' `ReinsNetworkGuard`). | Not a reply: reported when the process exits (the requests on stderr) or thrown by the guard's `check()` in a test. |

Drivers that act on a real screen add these:

| Code | Exit | When |
| --- | --- | --- |
| `person-active` | 2 | Someone is using the machine. A driver that moves, focuses or types on a person's screen MUST refuse rather than interrupt them; `fix` says how long to wait. |
| `app-protected` | 2 | The target is something agents never drive: an app whose own policy refuses automation, a password or administrator prompt, a consent the agent's own tools didn't raise, a device-management or security setting. `fix` names the sanctioned route, if there is one. |
| `permission-missing` | 2 | The driver lacks an operating-system permission it needs (Accessibility, Screen Recording). `fix` names the person step; a driver MUST NOT raise the permission prompt itself when nobody is there. |
| `until-not-met` | 1 | A step's condition (§6) didn't hold in time. |

An agent reads the code; it doesn't retry blindly. A new code MUST be a lowercase slug with a fixed exit, and SHOULD be added to this table.

## 5. Exit codes

A process that runs a sequence of lines (a command line, a journey) exits **0** when every line succeeded, **2** when one was refused, **1** when one failed, and **3** when the network was attempted. The highest-priority outcome wins: 3, then 1, then 2. Exit 3 means nothing for a driver whose transport is itself the network; such a driver doesn't use it.

## 6. Journeys

A journey is a flow worth keeping, as data:

```json
{ "name": "new-window", "steps": [
  { "action": "menu", "input": { "item": "File > New Finder Window" }, "until": { "focus": "Recents" } },
  { "action": "press_key", "input": { "key": "cmd+w" } },
  { "until": { "state.app.front": true }, "timeout_ms": 2000 }
] }
```

- A step is `{action?, input?, until?, timeout_ms?}`. `until` maps dotted paths into the screen to expected JSON values; a number expected at an array compares its length. A driver MAY define more step fields for its own addressing (Reins for any Mac app adds `app`).
- A driver runs a step's action, then polls until `until` holds or `timeout_ms` passes (default 2000; OuroReins polls every 5 ms). A step with only `until` just waits.
- A journey stops at the first refusal, failure or unmet `until`, and reports what it waited for, the last screen, and the `do` lines that replay it up to that point.

## 7. Optional: batches and diffs

These make a remote driver fast. Each request costs a round trip, and each reply carries a screen. A driver that offers them says so in `help`.

**Batch.** `{"id":4,"op":"batch","steps":[…]}` runs journey steps (§6) on the driver's side in one round trip, checking every `until` there. The reply is `{ok, error?, steps, screen}`, where `steps` has one `{n, action?, ok, ms, error?}` per step that ran, and `screen` is the screen after the last one. A six-field form fill is one request.

**Revisions and diffs.** A driver MAY give each screen a `rev`: a hash of `focus`, `path`, `state` and `actions` that changes whenever any of them changes. A client then sends the `since` rev it holds, and the driver answers with only what changed:

```json
{ "rev": "b81c…", "since": "6c64…",
  "put": [ { "ref": "searchfield", "role": "searchfield", "value": "pasta" } ],
  "del": ["row[notes.txt]"],
  "order": ["button[close]", "searchfield", "row[report.pdf]"],
  "state": { "window": { "title": "Search" } } }
```

`put` adds or replaces elements by their stable address, `del` removes them, `order` is given only when the order changed, `state` replaces top-level state keys, `state_del` removes them, and `actions_put` and `actions_order` do the same for actions. `{"rev": "…", "same": true}` means nothing changed. A client that doesn't hold `since` asks again without it and gets the whole screen. A driver MAY also send narrowed enums that only repeat what the elements already say as `{"$from": "<capability>"}`, which the client rebuilds from the elements.

## 8. Transports

The same lines and replies travel over:

- **Command line.** Arguments are lines; with none, stdin. One reply per line on stdout, then the exit code (§5).
- **Unix socket.** One connection carries any number of lines; requests from every connection run one at a time.
- **In-process.** A test calls the session directly (OuroReins' `ReinsSession`, `ReinsJourney`).
- **Remote.** Any message bus that delivers a request line to the driver and the reply back. The driver runs next to the screen; only lines cross the network, so batches and diffs (§7) matter most here.

## Implementations

- **OuroReins** (this package): any Ouro UI app, headless, from its view models. [Guide](README.md).
- **Reins for any Mac app**: a whole Mac's UI through the accessibility tree, with a pixel layer for what has no tree. [Section in the guide](README.md#reins-for-any-mac-app).

## Changes

- **1** (2026-11-08): first published, from OuroReins as built and the first driver for whole Macs ([#76](https://github.com/ourostack/ouro-ui-apple/issues/76)). Adds `person-active`, `app-protected`, `permission-missing`, `until-not-met`, batches and diffs.
