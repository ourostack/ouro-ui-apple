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

## An app's brand colour

``OuroTheme/withPrimary(light:dark:lightLabel:darkLabel:)`` keeps a theme and changes only its primary in each mode,
with the focus rings and sidebar colours that follow it. The label on the primary is white or ink, whichever reads
better, unless you give one. So `OuroTokens.pearl.withPrimary(light: ribbon, dark: nightRibbon)` is Pearl with the
app's buttons, and Increase Contrast still raises it as it does Pearl's. ``OuroColors/withPrimary(_:label:)`` does the
same for one mode.

## Headings

``OuroTheme/heading`` is the theme's `--font-heading` stack. The kit sets its titles in it where web does: the empty
state's, the page header's, the card's and the sheet's (``SwiftUI/Font/ouroHeading(_:weight:in:registered:)``). The
first family the app has wins, as with a text role, and a generic family picks the system design. So Cookbook's titles are
Fraunces when the app bundles it, then Georgia, and Pearl's stay the system font. ``OuroFont/heading(_:registered:)``
says which one a theme resolves to.

## A theme's own tokens

``OuroTheme/extras`` holds the tokens only one theme defines, such as Cookbook's `sj-*` colours, lengths, shadows and
text roles; every other theme's are empty. ``OuroThemeExtras/color(_:_:)`` answers nil for a colour the theme lacks.

A text role becomes a font with ``SwiftUI/Font/ouro(_:in:registered:)``: the first family in web's `font-family` stack
the app has registered (``OuroFont/isRegistered(_:)``), scaled with Dynamic Type relative to the role's text style. A
generic family in the stack (`serif`, `system-ui`) picks the system font's design, so with no bundled fonts a serif
role is New York. `.ouroType(_:)` also sets the role's letter spacing and line height, both scaled with text size, so an
eyebrow keeps its tracked look at every size. The line height is the role's CSS line height: `lineSpacing` adds only
what the font's own line (``OuroFont/naturalLineHeight(_:in:registered:)``) lacks. `Font.ouro` alone sets the font, not
the spacing.

A registered family renders the face with the role's weight, by PostScript name (``OuroFont/face(family:weight:)``), so a
missing weight never quietly renders regular; a debug build logs a fault. Assert an app's bundled fonts load with
``OuroFont/isAvailable(family:weights:)``. Spoonjoy's cookbook roles come from its web stylesheet (credit: Spoonjoy).
