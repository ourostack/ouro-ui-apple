# Haptics

A named table of moments, so the same moment always feels the same.

## Overview

| Moment | Feedback |
|---|---|
| ``OuroHapticMoment/selected`` | selection |
| ``OuroHapticMoment/checked`` | selection |
| ``OuroHapticMoment/stepped`` | selection |
| ``OuroHapticMoment/turned`` | light impact, 0.7 |
| ``OuroHapticMoment/started`` | medium impact |
| ``OuroHapticMoment/finished`` | success |
| ``OuroHapticMoment/warned`` | warning |
| ``OuroHapticMoment/failed`` | error |

```swift
Toggle("Butter", isOn: $hasButter)
    .ouroHaptic(.checked, trigger: hasButter)
```

Each feedback has a ``OuroHapticMoment/Feedback/label`` a person can read ("Light impact, 70%"), which is also
its `description`; the gallery's Feel page lists the table with it.

``OuroHaptics/play(_:)`` plays one outside a view and returns false, doing nothing, where there is no haptics engine.

Credit: Spoonjoy's `KitchenHapticMoment` table (ingredient checked, step turned, timer started and finished) and
Gatefold's light 0.7 impact (its bookmark), which `turned` takes in place of Spoonjoy's full-strength light impact.
