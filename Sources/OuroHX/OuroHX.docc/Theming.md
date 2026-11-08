# Theming

Put a theme in the environment and read its colours and radii.

## Overview

`.ouroTheme(_:)` sets ``SwiftUICore/EnvironmentValues/ouroTheme`` and ``SwiftUICore/EnvironmentValues/ouroColors``.
The colours follow the colour scheme and Increase Contrast as they change, and the theme's primary becomes the tint.

Radii follow web's scale: `theme.radius(.sm)` is `--radius-sm`, `theme.radius(.xl2)` is `--radius-2xl`. Each step is
the theme's base radius times ``OuroRadius/scale``.

Colour names are HX's CSS variables in camel case, so `--primary-foreground` is `primaryForeground` here and on web.

`OuroTokens.Duration` is core's `ouro.duration` group, named like `Ease`, `Spring` and `Press`. Inside `OuroTokens` it
shadows `Swift.Duration`; outside it does not. Write `Swift.Duration` in an extension of `OuroTokens` if you ever need
both (see `docs/decisions/2026-11-03-package-shape.md`).

## A theme's own tokens

``OuroTheme/extras`` holds the tokens only one theme defines, such as Cookbook's `sj-*` colours, lengths, shadows and
text roles; every other theme's are empty. ``OuroThemeExtras/color(_:_:)`` answers nil for a colour the theme lacks.

A text role becomes a font with ``SwiftUI/Font/ouro(_:in:registered:)``: the first family in web's `font-family` stack
the app has registered (``OuroFont/isRegistered(_:)``), scaled with Dynamic Type relative to the role's text style. A
generic family in the stack (`serif`, `system-ui`) picks the system font's design, so with no bundled fonts a serif
role is New York. `.ouroType(_:)` also sets the role's letter spacing and line height, both scaled with text size, so an
eyebrow keeps its tracked look at every size. Spoonjoy's cookbook roles come from its web stylesheet (credit: Spoonjoy).
