# Motion

Core's durations, eases, spring and press, with one Reduce Motion rule.

## Overview

``OuroMotion/step(_:reduceMotion:)`` turns a ``OuroMotion/Kind`` into a ``OuroMotion/Step``: the spring, a timed curve,
or, under Reduce Motion, a crossfade of `OuroTokens.Duration.base` (0.2 s). A press under Reduce Motion does not scale.

```swift
Image(systemName: "heart.fill")
    .scaleEffect(isFavourite ? 1.2 : 1)
    .ouroAnimation(.spring, value: isFavourite)

Button("Cook") { start() }
    .buttonStyle(.ouroPress)
```

For an app's own motion there is a small named set of springs, Apple's own presets: ``OuroMotion/Kind/snappy`` (quick,
a touch of bounce), ``OuroMotion/Kind/smooth`` (unhurried, none), ``OuroMotion/Kind/bouncy`` (a clear overshoot) and
``OuroMotion/Kind/interactive`` (following a finger). They take the same Reduce Motion rule.

```swift
withOuroAnimation(.bouncy, reduceMotion: reduceMotion) { isFavourite.toggle() }
```

Credit: the crossfade rule is Spoonjoy's `KitchenMotion.step(_:reduceMotion:)`; Gatefold's `Motion` springs follow the
same rule.
