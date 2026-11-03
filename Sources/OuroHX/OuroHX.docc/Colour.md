# Colour

Contrast checks, readable labels, increased-contrast colours and colours that adapt by themselves.

## Overview

- ``OuroColor/contrastRatio(_:_:)-(Color,Color)`` is WCAG 2's ratio, from 1 to 21.
- ``OuroColor/readableLabel(on:)`` picks white or HX's ink for a fill, whichever reads better.
- ``OuroColor/increasedContrast(_:)`` raises every text colour to 7:1 on its surface and every line to 3:1. Core v0.1.0
  has no high-contrast tokens, so these are derived; when core ships them, this follows core.
- ``OuroColor/dynamic(light:dark:increasedLight:increasedDark:)`` and ``OuroColor/dynamic(_:)`` make colours that
  follow light, dark and Increase Contrast without the environment: for UIKit and AppKit views, widgets and snippets.

The gallery app (`Examples/OuroHXGallery`) shows every theme's colours in light, dark and increased contrast.

Credit: the contrast maths is Spoonjoy's `KitchenContrast`; the label choice is Gatefold's `ThemePalette.onAccent`; the
four-way adaptive colour is Gatefold's `Color(light:dark:highContrastLight:highContrastDark:)`.
