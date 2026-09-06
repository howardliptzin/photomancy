# Photomancy

Divination by photograph.

A native macOS instrument for finding photographic sequences by chance: import a
set of photographs, roll them into a grid, keep what surprises you, roll the rest
again.

The screen is the instrument. The grid fills the window and reflows as you resize
it — 64 photographs at 8 × 8 with a hairline gap, or six at 3 × 2 — so sequencing
happens at whatever density the work wants. Printing takes what is on screen and
scales it onto a single sheet; it exists to make a hard copy of a result, not to
constrain how you arrive at one.

Free, open source, and distributed through the Mac App Store.

## Status

In development; nothing to install yet.

Working: import and collections, security-scoped bookmarks, the two-tier thumbnail
cache, the layout function and the sheet, and the loop — randomize, select, pin,
remove, undo. In daily use, which is where the last few rounds of changes came from.

Not built: the lightbox, drag to reposition, the settings interface, and printing.

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
