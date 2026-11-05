---
name: ouro-reins
description: Drive an Ouro UI app headless with Ouro Reins (`ls` and `do`), to check a flow, reproduce a bug or write a behaviour test without a simulator. Use when an app or its package has an OuroReins executable, socket or ReinsDrivable shell.
---

# Driving an app with Ouro Reins

1. **Find the driver.** Look for an executable target that calls `ReinsCommandLine.run` (`swift run <name> help`),
   or a debug app logging a `ReinsSocketServer` path (`nc -U <path>`). No driver means the app hasn't adopted Reins;
   use XCUITest instead.
2. **Look before acting.** `ls` returns `focus`, `path`, `state`, `context` and `actions`. Only the listed actions
   exist right now; each lists its input schema, often narrowed to the exact values allowed.
3. **Act.** `do <action> <json>`. Every reply carries the new screen, so you rarely need another `ls`.
4. **Read refusals; don't retry blindly.** `action-unavailable` names the actions that are available.
   `input-invalid` names the JSON path that's wrong. `action-failed` (exit 1) means the app threw: that's a finding.
5. **Exit 3 means the flow touched the network.** Report the listed requests; the fix is a fixture injected through
   the type's constructor, never a looser guard.
6. **Write it down as a journey.** A flow worth keeping becomes a `ReinsJourney` test: `do(action, input, until:)`
   per step, conditions on `focus` and `state`. Its failure prints the last screen and the replay lines.
7. **Know what it can't see.** Reins drives behaviour, not pixels. Layout, motion and jank are Ouro Feel's; what the
   app tells Siri and VoiceOver is the Ouro AX X-ray's. Don't claim a screen *looks* right from `ls`.
