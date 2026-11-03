# ``OuroHXTesting``

Test helpers for apps that use Ouro HX: snapshots, accessibility audits and the iPhone Duo hinge.

## Overview

- ``OuroSnapshot`` renders a view in light, dark and increased contrast and compares it with a recorded PNG. Set
  `OURO_SNAPSHOT_RECORD=1` to record. It does not need XCTest.
- `XCUIApplication.ouroAccessibilityAudit(for:knownIssues:)` runs Xcode's accessibility audit and fails on every issue
  you have not named.
- ``OuroDuoHinge`` folds and opens the iPhone Duo simulator from a UI test. A Mac job runs
  `swift run ouro-devicehub serve "$DIR"` and the test gets `TEST_RUNNER_OURO_DUO_POSTURE_DIR=$DIR`.

Credit: the Duo request files are Spoonjoy's `DuoHinge`; `ouro-devicehub` is the `devicehub.swift` that Spoonjoy and
Gatefold each carried.

## Topics

- ``OuroSnapshot``
- ``OuroDuoHinge``
