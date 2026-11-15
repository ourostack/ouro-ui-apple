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

## The components

``OuroFoldReader`` also puts the posture in the environment (`\.ouroFoldPosture`), so the kit's components inside it
follow the fold:

- **Sheet.** Held as a tabletop, an `.ouroSheet` rests on the lower half, the part flat on the table: never taller
  than that half, so it doesn't cross the fold and what is above stays in view; its content scrolls when there is
  more (``OuroSheetMetrics/detents(_:fitted:posture:)``). In a book, closed or on one page it keeps its own detents.
- **Item and card** have no posture of their own. Place them in a pane (`split.first` or `split.second`) and they
  lay out in that pane's width, as they do in any narrow container: rows keep their actions beside the words and
  stack them only at the accessibility sizes, and a card's action moves under its title the same way.

CI checks both on an iPhone Duo simulator whose hinge Device Hub really moves (the gallery's `FoldPostureTests`, in
the `gallery-duo` job): a sheet asking for full height reaches the top half when open flat and rests below the fold as
a tabletop, and the items and cards pages, placed in a book's leading page, keep every control left of the fold and
pass the accessibility audit.

Credit: Spoonjoy's `TabletopLayout`, `FoldBand` and `FoldRegionChoice` (the tabletop split, margins and angle bands)
and Gatefold's `ReaderLayoutResolver`, `FoldReader` and `HingeObserver` (the book spread, the inactive-region rule and
the spine shadow).
