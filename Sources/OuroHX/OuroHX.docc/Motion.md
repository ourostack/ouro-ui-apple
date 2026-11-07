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

## Filming motion on a test's clock

A UI test that films OuroHX's motion with Ouro Feel can run it on a clock the test moves one tick at a time, so a busy
machine films the same frames as an idle one. The app installs an ``OuroMotionClock`` as ``OuroMotion/clock`` and
advances it on each tick the test posts (`FeelClock.darwinNotification(_:)`); every animation OuroHX makes through
``OuroMotion`` then holds still between ticks and moves on by one tick at each. Install one only for such a test: with
nothing advancing it, OuroHX's motion never finishes. The HX gallery's `-clock 1` and its toast-stack Feel test show the
whole loop. A wall-clock wait in the app (a toast's countdown, an animation's `delay`) still runs on the wall clock.

```swift
let clock = OuroMotionClock()
OuroMotion.clock = clock
// On each tick the test posts:
clock.advance(by: 0.05)
```

Credit: the crossfade rule is Spoonjoy's `KitchenMotion.step(_:reduceMotion:)`; Gatefold's `Motion` springs follow the
same rule.
