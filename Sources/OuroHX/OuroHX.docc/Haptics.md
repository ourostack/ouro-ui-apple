# Haptics

A named table of moments, so the same moment always feels the same.

## Overview

| Moment | Feedback |
|---|---|
| ``OuroHapticMoment/selected`` | selection |
| ``OuroHapticMoment/checked`` | selection |
| ``OuroHapticMoment/stepped`` | selection |
| ``OuroHapticMoment/turned`` | light impact, full strength |
| ``OuroHapticMoment/started`` | medium impact |
| ``OuroHapticMoment/finished`` | success |
| ``OuroHapticMoment/warned`` | warning |
| ``OuroHapticMoment/failed`` | error |

```swift
Toggle("Butter", isOn: $hasButter)
    .ouroHaptic(.checked, trigger: hasButter)
```

Each feedback has a ``OuroHapticMoment/Feedback/label`` a person can read ("Medium impact" for `started`, "Light impact, 70%" for one at 0.7), which is also
its `description`; the gallery's Feel page lists the table with it.

``OuroHaptics/play(_:)`` plays one outside a view and returns false, doing nothing, where there is no haptics engine.

Credit: Spoonjoy's `KitchenHapticMoment` table (ingredient checked, step turned, timer started and finished) and
Gatefold's light impact (its bookmark). `turned` took Gatefold's 0.7 until Spoonjoy's adoption (W10) found it too
faint for a step turned mid-cook, felt through a busy hand; it is Spoonjoy's full-strength light impact again.
