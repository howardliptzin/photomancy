# Photomancy

Divination by photograph.

A native macOS instrument for finding photographic sequences by chance: import a
set of photographs, roll them into a grid, pin what belongs, roll the rest
again, and move frames into place as a sequence forms.

The screen is the instrument. The grid fills the window and reflows as you resize
it — 64 photographs at 8 × 8 with a hairline gap, or six at 3 × 2 — so sequencing
happens at whatever density the work wants. Printing takes the rectangles already on
screen and applies one uniform scale onto a single sheet, so what comes out is what
you arranged; it exists to make a hard copy of a result, not to constrain how you
arrive at one.

Open source under the MIT licence. It will be sold on the Mac App Store; the source
stays here for anyone who would rather build it themselves.

## Status

In development; nothing to install yet. M1–M5 are complete and in daily use. What
remains before the app is complete: sizing the memory cache from the window. Then a
free public beta, through TestFlight and a notarised download here.

Working: import and collections, security-scoped bookmarks, the two-tier thumbnail
cache, the layout function and the sheet, and the loop — randomize, select, pin,
remove, undo. From M4: drag a photograph onto a cell to move it there and pin it; the
lightbox, which names the file under each photograph, because reviewing often means
choosing between near-identical frames and the name is what tells them apart; and
per-collection settings — columns, rows, gap, background and cell shape. All Photos is
the union of the collections.

Since M4: move a selection into another collection, new or existing — from the Edit
menu, a right-click on a photograph, or by dragging onto the sidebar — for when rolling
one collection shows that some of it belongs somewhere else. And a drag carries the
whole selection: several frames gather into a stack under the pointer and land as one
run, in order, pinned where they are dropped.

From M5: printing. ⌘P opens the print panel on the collection's paper, states what a
cell and a gap will measure in millimetres, and updates as you change paper — and
⇧⌘E exports the sheet as a PDF. Print never draws from the thumbnail cache: it decodes
the originals at the size they print, 360 pixels per inch, never past the original.
The printed sheet is the sheet on screen, which `Scripts/verify-print.sh` checks by
rasterising the PDF and measuring each photograph's edges against the window's own
rectangles.

Also from M5: **Relink…**, for a photograph the app can no longer read. Point it at the
file, or at the folder its photographs are in now, and every one that matches is fixed
at once. Matched strictly by contents — a re-exported edit is a different photograph and
will not relink. Note that a photograph you merely *move* never goes missing: bookmarks
follow a file across a move or a rename. What needs relinking is a file that has been
replaced — restored from a backup, synced down, or copied from another volume.

Much of this came from using it.

## Building

Requires Xcode 16 or later, macOS 14 or later, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

The Xcode project is generated; `project.yml` is the source of truth.

```
xcodegen generate
xcodebuild -project Photomancy.xcodeproj -scheme Photomancy build
```

Tests — logic only, no app host, no window server:

```
xcodebuild -project Photomancy.xcodeproj -scheme PhotomancyCoreTests test
```

### The relaunch check

Photomancy is sandboxed, so it may only reopen a photograph if it saved a
security-scoped bookmark at import. No in-process test can prove that works: a
URL stays authorised for the life of the process. This script imports, quits,
deletes the thumbnail cache, and relaunches, so what appears on the second
launch can only have come from the originals.

It needs photographs to work with. `TestPhotos/` is ignored by git, so put a
handful of your own there first — a mix of JPEG, HEIC and PNG is the useful case.

**It deletes the app's whole library** to start from a clean slate. If you have real
collections, back up the container's `Data` folder first and put it back afterwards;
the script refuses to run over an existing library unless `PHOTOMANCY_WIPE_LIBRARY=1`
is set.

```
./Scripts/verify-relaunch.sh
```

Pass a different app or folder as arguments if you want:
`./Scripts/verify-relaunch.sh path/to/Photomancy.app ~/some/photos`

### Running it

Builds the current branch, replaces any running copy, and launches it.

```
./Scripts/run.sh
```

### Checking the print path

Renders real photographs, rasterises the PDF at 300 ppi, and compares each
photograph's edges with the window's rectangles under the print transform. Needs no
library and destroys nothing.

```
./Scripts/verify-print.sh
```

### Measuring

`photomancy-bench` links the same code the app does and measures decoding on a
real photo library.

```
xcodebuild -project Photomancy.xcodeproj -scheme photomancy-bench -configuration Release build
./build/DerivedData/Build/Products/Release/photomancy-bench ~/Pictures --count 60
```

## Licence

MIT — see [LICENSE](LICENSE).

Made by Howard Liptzin · [luna-park.com](https://luna-park.com)
