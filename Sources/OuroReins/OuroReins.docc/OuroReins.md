# ``OuroReins``

Ouro Reins: an app's screens as state and actions, driven with `ls` and `do`, headless, with the network blocked.

## Overview

An app builds a tree of ``ReinsNode``s from the models it already has: each node's state as JSON, the
``ReinsAction``s it offers and one child. The deepest node is the focus. A ``ReinsSession`` lists the focus
(``ReinsScreen``) and runs actions, refusing one that isn't offered, or input that doesn't match its ``ReinsSchema``,
with an `OuroAX.Problem` naming what is allowed. Containers lend actions: ``ReinsNode/stack(_:depth:goBack:child:)``
lends `goBack`, ``ReinsNode/tabs(_:selected:tabs:select:child:)`` lends `selectTab`.

- ``ReinsInput`` derives an action's input schema from `Decodable`; ``ReinsEnumerable`` makes a string enum `oneOf`.
- ``ReinsAction/narrowed(_:)`` limits an input to the values valid on screen now.
- ``ReinsWire`` speaks one JSON line per request (`ls`, `do <action> <json>`, `help`, or the JSON form with an `id`);
  ``ReinsCommandLine`` runs it from arguments or stdin with exit codes 0, 2 (refused), 1 (action failed) and 3 (the
  network was attempted).
- ``ReinsJourney`` drives a flow in a test, polling each step's condition and failing with the last screen and the
  lines to replay it.
- ``ReinsNetworkGuard`` fails and records every URL load while it runs; `check()` throws `network-attempted` (exit 3).
- `ReinsSocketServer` serves the wire protocol on a Unix socket in debug builds only.

The idea and most of the shape come from Shopify's [Reflex](https://shopify.engineering/reflex). The guide for app
authors and agents is `docs/ouro-reins/README.md`; the decisions are `docs/decisions/2026-11-05-ouro-reins.md`.
Spoonjoy's spike (Kitchen, recipe, cook mode and back) is the first app driven this way.
