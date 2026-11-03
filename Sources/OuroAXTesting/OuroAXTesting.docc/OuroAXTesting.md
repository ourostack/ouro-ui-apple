# ``OuroAXTesting``

Test helpers for Ouro AX. The App Intents X-ray arrives later; today, the parts of a Siri evaluation that need no Siri.

## Overview

- ``OuroAXTesting/Wordings`` holds the four ways to ask for one thing: direct, indirect, incomplete and unexpected.
- ``OuroAXTesting/PassRate`` judges a scenario over ``OuroAXTesting/recommendedRuns`` runs, since Siri varies.
- With the Xcode 27.3 beta SDK, `Wordings.scenarios(_:)` turns wordings into SiriEvaluations scenarios.
