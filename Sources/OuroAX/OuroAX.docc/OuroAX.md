# ``OuroAX``

Ouro AX for Apple: outcomes and problems that read the same to a person, Siri and an agent.

## Overview

- ``OuroAX/Outcome`` mirrors web's `ax-outcome` (`outcome/1`) field for field, `needs-human` included on the wire.
  ``OuroAX/Outcome/validate()`` applies the same rules as the TypeScript kit's `validateOutcome`.
- ``OuroAX/Problem`` mirrors `ax-problem`: `<thing>: <problem>. Fix: <fix>.`
- ``OuroAX/ExitCode`` and ``OuroAX/ExitTable`` keep a tool's exit codes: 0 ok, 1 error, 2 usage, then the tool's own.
- ``OuroAXEntity``, ``OuroAXEntitySource`` and ``OuroAXEntityQuery`` answer App Intents entity queries, string
  matching included, from one source.
- ``OuroAXOutcomeIntent`` speaks an outcome's summary or throws its problem.
- ``OuroAXPackage`` is the `AppIntentsPackage` an app includes.

The `ouro-ax-skills` linter and its build-tool plugin check app-skills bundles: `swift run ouro-ax-skills lint
Skills.skillsbundle`.

Siri AI Developer Preview code (the `OuroAXToolIntent` alias for tool intents) compiles only with the Xcode 27.3 beta
SDK, behind `#if OURO_SIRI_AI_SDK || canImport(AppIntents, _version: 301.2)`.
