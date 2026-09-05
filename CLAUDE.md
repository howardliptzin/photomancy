# Photomancy — project contract

Native macOS app. Free, open source, shipped via the **Mac App Store** (signed,
sandboxed). SwiftUI, Swift 6, macOS 14+.

**Full brief (rationale lives there, not here):**
https://claude.ai/code/artifact/5917d4a2-04fb-4561-87ce-7844ceb530ba
Read it before writing code. Section numbers below refer to it.

**Status:** nothing built yet. First milestone is M1 (§08).

## What this is

**Photomancy** — divination by photograph. A **chance-operation instrument** for
finding photographic sequences: import photos, roll them into a grid, pin what
surprises you, re-roll the rest. It also prints.

It is not a layout tool that happens to shuffle. Randomness is the method, not a
starting point — this is aleatory practice (surrealist chance operations), where
serendipity is the product. Curation happens at import. **Never re-frame it as
narrative or editorial sequencing.**

## Architecture — settled

- **One pure `layout()` function** returns cell rectangles from
  `(cols, rows, gap, cellAspect, canvas)`. Screen positions views with them; print
  draws into a `CGContext` with them. Geometry shared, drawing not.
- **Fit is the default cell mode.** Fill centre-crops, and v1 has no crop control,
  so that crop is uncorrectable. A crop is also a decision the *tool* made — not
  the photographer, not chance.
- **Cell shape is a per-collection setting**, starting at **square**. Square is the
  only shape where a photograph and its transpose occupy the same area, and it is
  the minimax choice — under random placement the worst-placed frame is a recurring
  event, not an edge case. Options: square, 3:2, 4:3, match the page, derived from
  the collection. `derivedFromCollection` is a choice someone makes and never a
  default: it would reflow a sheet on import with nothing on screen to say why.
- **Paper is a per-collection setting**, starting at **A4 landscape** — which makes
  the default output a contact sheet. It is a sheet setting, not a printer setting:
  "what you see is one page" means the paper's proportions shape the screen.
- **Every sheet setting is per collection**, All Photos included, and every one of
  them decodes with a default when its key is missing. Settings are the part of the
  store that grows, and `LibraryStore.load()` refuses to overwrite a file it could
  not read — so a throw on an unknown key would show an empty grid over a perfectly
  intact library.
- **Never `LazyVGrid` for the sheet** — its geometry is invisible to the print path
  and the two will drift.
- **Print draws from full-resolution images**, never screen thumbnails.
- **What you see is one page.** No pagination in v1.
- **Security-scoped bookmarks** stored at import and resolved before every read.
  Without this, collections are empty on second launch. Build it right on day one.
- **Content hash** identifies a photo (survives renames) and keys the thumbnail cache.
- **Decode at display size** via ImageIO, off the main thread. Two-tier cache:
  in-memory `NSCache` + on-disk in Application Support.
- Collections are app-managed reference lists, **not folders**. Plain `Codable` store.
- **All Photos** is a virtual collection: every reference, de-duped by content hash.
  Own pins, own settings. The first-launch view.

## M1 is not done until

1. **The app is sandboxed from the very first build** — `com.apple.security.app-sandbox`
   and `com.apple.security.files.user-selected.read-only` in the entitlements. With the
   sandbox off, missing-bookmark bugs are invisible and every path looks correct.
   Verify with `codesign -d --entitlements - <path>.app`, not by assuming.
2. **Quit the app, relaunch, and the imported photographs still render.** Nothing short
   of this proves the bookmarks work. An in-process test passes even when they are
   broken, because the URL stays authorised for the life of the process — it measures
   the proxy, not the thing.
3. **The reference store exposes no bare `URL`** — only a scoped accessor, e.g.
   `withAccess { url in … }`, that starts and stops access around every read. If a raw
   URL cannot be obtained, no later code can forget to redeem the bookmark.
4. **`bookmarkDataIsStale` is handled** by re-creating and re-saving the bookmark.

## Interaction — settled

Every core action has **both a pointer route and a keyboard route**. Neither is the
poor relation.

| | |
|---|---|
| `Space` | Randomize — **also a toolbar button** |
| Arrow keys | Move focus ring between cells |
| `P` | Pin/unpin the focused photo |
| Click | Pin/unpin in place |
| Double-click | Lightbox |
| Drag | Move to a cell and pin there |
| `←` `→` | In lightbox: move through photos |
| `Esc` | Close lightbox |
| `⌘Z` / `⇧⌘Z` | Step through arrangements |
| `⌘P` | Print (also yields PDF) |

- **Undo spans shuffles.** Non-negotiable — it's what makes gambling on chance safe.
- Click pins, double-click zooms. This is deliberately **inverted** from the web app.
- Randomize animates cells to new positions (~200ms), respecting
  `prefers-reduced-motion`. The movement is how the eye registers what changed.

## Look and feel

Essential and unobtrusive; everything secondary to the photographs. Chrome earns its
place or goes. Controls small, quiet, always in the same place.

Standards, in order: **intuitive** (nothing needs explaining twice) → **consistent**
(same gesture, same meaning, everywhere) → **fast** (nothing perceptibly waits).

**The UI will be iterated heavily. That is planned, not failure.** Keep view code thin
and logic-free so it can be torn up without touching layout, caching or state.

## Do not build (v1)

Watched folders · publishing to a server · constraint rules for the shuffle · editing
or cropping · multi-page contact sheets · captions/metadata overlays · iCloud sync ·
soft proofing or CMYK.

Each sounds small and each moves this toward being a weaker Lightroom. If I propose
one, refuse and point here.

## Working conventions

- Build and test from the shell (`xcodebuild`), not the Xcode GUI.
- **Push correctness into pure, testable functions** — `layout()`, hashing, cache keys.
  I can verify those alone with XCTest; I cannot inspect a running SwiftUI view the
  way I can a DOM. Thin views, tested logic.
- Small, frequent commits.
- Plan before coding on the layout engine and the print path.
- A failed verification may be a failed measurement — prove the instrument before
  chasing the bug.

## Identity — settled

- **Bundle ID:** `com.luna-park.Photomancy`. Permanent once shipped.
- **App Store developer name:** `Howard Liptzin`. Individual enrollment — Luna Park is
  not a legal entity, and Apple only permits a trade name on an Organization account.
  Not revisitable: the developer name is fixed at first app-record creation.
- **luna-park.com** everywhere else: support and contact URLs, marketing URL, GitHub
  org, copyright string, About box.

## Unsettled — ask, don't assume

- **What the canvas is.** Paper is A4 landscape; the printable area is not the
  paper. Either `layout()` fills the printer's imageable rect — correct, but the
  on-screen sheet then changes shape with the printer — or the app owns a margin
  and clamps it to the imageable rect at print time — predictable, and the same on
  every machine. Proposal: the latter, with the outer margin equal to `gap`, so
  "padding, exact to the pixel" means one number everywhere. Needed before M2.
- **Print resolution** for converting the pixel `gap` to a physical measure. 300 dpi
  unless there is a reason otherwise. Needed at M5, not before.
