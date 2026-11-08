# 2026-11-08: The Reins protocol is published on its own

Status: accepted ([#76](https://github.com/ourostack/ouro-ui-apple/issues/76)).

## Context

OuroReins defined its wire format in Swift only (`ReinsWire`, `ReinsScreen`, `ReinsReply`). A second driver now exists: Reins for any Mac app, which drives every app on a Mac through the accessibility tree, with a pixel layer for screens that have none, and runs across a network. Its first version inferred the protocol from the Swift code and got the envelope wrong (`refused` instead of `error`, `why` instead of `title`). An agent that learns one driver should be able to drive the other.

## Decision

1. **[PROTOCOL.md](../ouro-reins/PROTOCOL.md) is the contract**, versioned, transport-agnostic, with the Swift types as the reference. A wire change here updates it in the same pull request (AGENTS.md).
2. **Refusal codes are one registry** with fixed exits. The core codes are OuroReins' own. Drivers that act on a real screen add `person-active`, `app-protected` and `permission-missing`; journeys add `until-not-met`.
3. **Batches and diffs are optional** extensions for remote drivers, which pay a round trip per request: `batch` runs journey steps on the driver's side, and `rev`/`since` diffs send only what changed. OuroReins doesn't need either in-process.
4. **Exit 3 stays OuroReins'**: a driver whose transport is the network doesn't use it.

## Prior art

| Find | Verdict | Why |
| --- | --- | --- |
| [Shopify Reflex](https://shopify.engineering/reflex) | adopt (already) | `ls`/`do` over state and actions is where Reins came from. |
| [Playwright ARIA snapshots and role locators](https://playwright.dev/docs/aria-snapshots) | borrow | Role plus accessible name is the address that survives layout changes; Reins for any Mac app's refs (`button[Back]`) are the same idea. |
| [Model Context Protocol tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools) | borrow | Every tool carries a JSON Schema for its input; Reins narrows that schema to what's valid now. |
| [WebDriver](https://www.w3.org/TR/webdriver2/) and Appium | ignore | Element handles and sessions are stateful and verbose; Reins reads the whole screen as state every time. |
| [PiKVM's HTTP API](https://docs.pikvm.org/api/) | adopt (the pixel driver) | Snapshot, keyboard and mouse over HTTPS; GL.iNet's Comet runs a fork of it. |
| Model-driven computer use (screenshots read by a model) | ignore | Slow and non-deterministic; Reins is for flows that need neither. |
