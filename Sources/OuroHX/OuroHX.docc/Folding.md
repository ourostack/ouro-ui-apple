# Folding

Lay out around the iPhone Duo's fold: tabletop, book, closed or one page.

## Overview

``OuroFoldPosture/resolve(size:hinge:regions:rules:)`` is pure: give it the container size, the ``OuroHinge`` and the
`.division` reserved regions, and it returns the posture with its panes and fold band.

- A **vertical** fold in a wide container opens a **book**, even when the region is inactive (iOS marks the Duo's fold
  inactive while it lies flat). An active region wins over an inactive one.
- A **horizontal** fold in a tall container stands as a **tabletop** when it is active, or, when the hinge is bent
  between 60° and 150°, even when it is inactive. With a bend and no region, the tabletop splits at the middle of the
  screen.
- A pane shorter than 260 points, a region outside the container, or no hinge gives **single**.
- The fold band is at least 48 points (24 each side); a wider reported fold keeps its width.

``OuroFoldReader`` reads the regions and the hinge with iOS 27.1's `reservedRegions(kind:options:)` and `onHingeChange`,
behind `#available`; on earlier systems it always gives `.single`. ``OuroHinge/bend`` gives a spine shadow's depth.

Credit: Spoonjoy's `TabletopLayout`, `FoldBand` and `FoldRegionChoice` (the tabletop split, margins and angle bands)
and Gatefold's `ReaderLayoutResolver`, `FoldReader` and `HingeObserver` (the book spread, the inactive-region rule and
the spine shadow).
