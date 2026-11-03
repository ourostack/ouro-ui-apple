# ``OuroAXTesting``

Test helpers for Ouro AX: the parts of a Siri evaluation that need no Siri, and the App Intents X-ray.

## Overview

- ``OuroAXTesting/Wordings`` holds the four ways to ask for one thing: direct, indirect, incomplete and unexpected.
- ``OuroAXTesting/PassRate`` judges a scenario over ``OuroAXTesting/recommendedRuns`` runs, since Siri varies.
- With the Xcode 27.3 beta SDK, `Wordings.scenarios(_:)` turns wordings into SiriEvaluations scenarios.

## The App Intents X-ray

``AXXray`` checks a built app against Ouro AX for Apple's claims, vendored from ouro-ui-core as
``AXXray/ClaimSet/bundled()``.

- ``AXXray/Inventory`` reads the app's compiled App Intents metadata.
- ``AXXray/check(_:_:)`` checks every claim against the ``AXXray/Evidence``: the metadata, the skills linter's report,
  a behaviour run (``AXXray/ProbeResult``) and SiriEvaluations runs (``AXXray/SiriResults``). A lane with no evidence
  skips its claims and says what would check them.
- ``AXXray/report(_:_:name:bundleIdentifier:platform:commit:at:)`` summarises them in web's ax-xray shape;
  ``AXXray/Report`` renders as text, Markdown and HTML.
- ``AXXray/ProbePlan`` is what the behaviour stage runs; `OuroAXTestingProbe` runs it inside a test bundle.
- ``AXXray/SiriScenarioSet`` holds an app's Siri scenarios as data and writes their SiriEvaluations tests.
- ``XrayCLI`` is `ouro-ax-xray`.
