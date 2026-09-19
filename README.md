# Photomancy

Divination by photograph.

A native macOS instrument for finding photographic sequences by chance: import a
set of photographs, roll them into a grid, pin what belongs, roll the rest
again, and move frames into place as a sequence forms.

The screen is the instrument. The grid fills the window and reflows as you resize
it — 64 photographs at 8 × 8 with a hairline gap, or six at 3 × 2 — so sequencing
happens at whatever density the work wants. Printing takes what is on screen and
scales it onto a single sheet; it exists to make a hard copy of a result, not to
constrain how you arrive at one.

Open source under the MIT licence. It will be sold on the Mac App Store; the source
stays here for anyone who would rather build it themselves.

## Status

In development; nothing to install yet. M1–M4 are complete and in daily use; next is
M5, print and PDF. Once the app is complete there will be a free public beta, through
TestFlight and a notarised download here.

Working: import and collections, security-scoped bookmarks, the two-tier thumbnail
cache, the layout function and the sheet, and the loop — randomize, select, pin,
remove, undo. From M4: drag a photograph onto a cell to move it there and pin it; the
lightbox, which names the file under each photograph, because reviewing often means
choosing between near-identical frames and the name is what tells them apart; and
per-collection settings — columns, rows, gap, background and cell shape. All Photos is
the union of the collections.

Since M4: move a selection into another collection, new or existing — from the Edit
menu, a right-click on a photograph, or by dragging onto the sidebar — for when rolling
one collection shows that some of it belongs somewhere else.

Much of this came from using it.

Not built yet: printing and PDF.

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
