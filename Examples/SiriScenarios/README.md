# Siri scenario sets

Starter Siri evaluations for two of our apps, written as data. Each set has one or more scenarios of every wording
kind (direct, indirect, incomplete, unexpected) and says which intent Siri should call, with which parameters, which
entity it should find, and what each scenario needs on the device first.

| Set | App | Scenarios | Generated tests |
|---|---|---|---|
| [spoonjoy.scenarios.json](spoonjoy.scenarios.json) | Spoonjoy (`app.spoonjoy`) | 13 | [SpoonjoySiriEvaluation.swift](SpoonjoySiriEvaluation.swift) |
| [ouro-md.scenarios.json](ouro-md.scenarios.json) | Ouro MD (`bot.ouro.md`) | 8 | [OuroMDSiriEvaluation.swift](OuroMDSiriEvaluation.swift) |

Check a set against a build, and regenerate its tests:

```sh
swift run ouro-ax-xray scenarios --app path/to/App.app --set Examples/SiriScenarios/spoonjoy.scenarios.json
swift run ouro-ax-xray scenarios --app path/to/App.app --set Examples/SiriScenarios/spoonjoy.scenarios.json --swift > SpoonjoySiriEvaluation.swift
```

## Running one

The generated file compiles to nothing unless SiriEvaluations is there. To run it you need:

1. Xcode 27.3 beta.
2. A device on a 27.3 beta OS that supports Apple Intelligence, with Apple Intelligence and Siri turned on. Simulator
   will not load app skills.
3. The app, built with that Xcode and signed by the same team as the test target, installed and signed in.
4. What each scenario's `needs` says, on the device before the run:
   - Spoonjoy: a recipe named Shakshuka; a recipe open with a cookbook named Weeknights; cook mode on a recipe with
     several steps; cook mode on a step with a duration.
   - Ouro MD: a document named Trip notes.md that Ouro MD has opened before, and open for the onscreen scenario.
5. A test target containing the generated file, run with `-test-iterations 5` and `OURO_AX_SIRI_RESULTS` set to a file
   path in the test's environment.
6. Then `swift run ouro-ax-xray --app path/to/App.app --siri <that file> --siri-on "<device, OS>"` folds the pass
   rates into the report.

Not run yet: no machine here has the 27.3 beta, so the generated files are checked against the metadata but have not
been compiled against SiriEvaluations.
