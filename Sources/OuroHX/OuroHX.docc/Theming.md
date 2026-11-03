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
