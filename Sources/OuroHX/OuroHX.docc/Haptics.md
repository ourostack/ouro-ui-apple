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

``OuroHaptics/play(_:)`` plays one outside a view and returns false, doing nothing, where there is no haptics engine.

Credit: Spoonjoy's `KitchenHapticMoment` table (ingredient checked, step turned, timer started and finished) and
Gatefold's page-turn impacts.
