# Photomancy — project contract

Native macOS app. Free, open source, shipped via the **Mac App Store** (signed,
sandboxed). SwiftUI, Swift 6, macOS 14+.

**Full brief (rationale lives there, not here):**
https://claude.ai/code/artifact/5917d4a2-04fb-4561-87ce-7844ceb530ba
Read it before writing code. Section numbers below refer to it.

**Status:** M1 complete and verified — sandboxed scaffold, import, collections,
security-scoped bookmarks, thumbnail cache. Next is M2 (§08), the layout function,
and it gets planned before it gets coded.

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
- **The canvas is the window, not the page.** The sheet fills the window and
  reflows live as it is resized. Print does not recompute geometry: it takes the
  rectangles `layout()` already produced for the window and applies one uniform
  scale-and-translate onto the page's printable rect. Exact by construction rather
  than by discipline. Still one page, still no pagination, and no page breaks.
- **The grid block scales; the cell shape is held.** Filling the window means cells
  grow as large as they can while keeping their shape, centred, with dead space at
  two window edges. Cells never distort to fit a window. Screen space is free.
- **Fit is the default cell mode.** Fill centre-crops, and v1 has no crop control,
  so that crop is uncorrectable. A crop is also a decision the *tool* made — not
  the photographer, not chance.
- **Cell shape is a per-collection setting**, starting at **square**. Square is the
  only shape where a photograph and its transpose occupy the same area, and it is
  the minimax choice — under random placement the worst-placed frame is a recurring
  event, not an edge case. Options: square, 3:2, 4:3, derived from the
  collection. `derivedFromCollection` is a choice someone makes and never a
  default: it would reflow a sheet on import with nothing on screen to say why.
- **5 × 4 is a starting grid, not a constraint.** 8 × 8 at a 1 px gap and 3 × 2 at
  4 px are both ordinary uses. Never bound what can be played with on screen
  because of what it would cost on paper.
- **More photographs than cells: every roll samples a different subset** — which is
  more surprise per roll, not a shortfall. Fewer photographs than cells: the spare
  cells stay empty and show the background. Never repeat a photograph to fill a
  grid; a duplicate reads as a bug rather than a choice.
- **Nothing caps the grid by policy — find the limit by using the loop.** Memory does
  not grow with cell count: cells tile the window, so the decoded total tracks the
  window's *area*, not the number of cells. More cells means smaller ones. What binds
  first is the cold fill, which scales with cell count while each decode gets cheaper
  as cells shrink; every visit after the first comes from the disk cache and is
  trivial. Watch the first fill, not memory.
- **The memory cache limit is a function of window area, not a constant.** Thumbnails
  are bucketed up to 1.5× their cell, and a cell's bucket is its long edge, so the
  decoded total is roughly two to four times the window's pixel count in bytes — a 5K
  window is 130–270 MB. The current fixed 256 MB happens to fit that and will not fit
  the next display. Derive it.
- **An empty cell is background and nothing else.** No outline, no placeholder, no
  hint that a cell is there — identical on screen and on paper. A grid that is not
  full should look like a grid that is not full.
- **The gap is pixels on screen and proportional on paper.** Printing scales the
  sheet uniformly, so a 12 px gap is not a fixed physical measure — it is
  `gap ÷ window width × page width`, and it changes with the window. Report the
  resulting millimetres in the print dialog instead of pretending otherwise.
- **Paper is the print target**, remembered per collection, starting at **A4
  landscape** — which makes the default output a contact sheet. It does not shape
  the screen; it is consulted only when scaling a sheet onto a page.
- **Every sheet setting is per collection**, All Photos included, and every one of
  them decodes with a default when its key is missing. Settings are the part of the
  store that grows, and `LibraryStore.load()` refuses to overwrite a file it could
  not read — so a throw on an unknown key would show an empty grid over a perfectly
  intact library.
- **Never `LazyVGrid` for the sheet** — its geometry is invisible to the print path
  and the two will drift.
- **Print draws from full-resolution images**, never screen thumbnails.
- **Security-scoped bookmarks** stored at import and resolved before every read.
  Without this, collections are empty on second launch. Build it right on day one.
- **Content hash** identifies a photo (survives renames) and keys the thumbnail cache.
- **Decode at display size** via ImageIO, off the main thread. Two-tier cache:
  in-memory `NSCache` + on-disk in Application Support.
- Collections are app-managed reference lists, **not folders**. Plain `Codable` store.
- **All Photos** is a virtual collection: every reference, de-duped by content hash.
  Own pins, own settings. The first-launch view.

## M1 is not done until

1. **The app is sandboxed from the very first build** — `com.apple.security.app-sandbox`,
   `com.apple.security.files.user-selected.read-only` and
   `com.apple.security.files.bookmarks.app-scope` in the entitlements; the last is what
   permits a security-scoped bookmark to be created at all. With the sandbox off,
   missing-bookmark bugs are invisible and every path looks correct. Verify with
   `codesign -d --entitlements - <path>.app`, not by assuming — and check Release
   separately, where `get-task-allow` must not appear.
2. **Quit the app, relaunch, and the imported photographs still render.** Nothing short
   of this proves the bookmarks work. An in-process test passes even when they are
   broken, because the URL stays authorised for the life of the process — it measures
   the proxy, not the thing.
3. **The reference store exposes no bare `URL`** — only a scoped accessor, e.g.
   `withAccess { url in … }`, that starts and stops access around every read. If a raw
   URL cannot be obtained, no later code can forget to redeem the bookmark.
4. **`bookmarkDataIsStale` is handled** by re-creating and re-saving the bookmark.

All four are met. `Scripts/verify-relaunch.sh` is the standing regression for (2) and
should be run after anything that touches import, the store, or the cache — it deletes
the thumbnail cache before relaunching, which is the step that makes it mean anything.

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

Nothing open. New questions belong here, where they will be seen, rather than
buried in a commit message or a code comment.
