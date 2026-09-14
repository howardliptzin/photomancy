# Photomancy — project contract

Native macOS app. Free, open source, shipped via the **Mac App Store** (signed,
sandboxed). SwiftUI, Swift 6, macOS 14+.

**Full brief (rationale lives there, not here):**
https://claude.ai/code/artifact/5917d4a2-04fb-4561-87ce-7844ceb530ba
Read it before writing code. Section numbers below refer to it.

**M2 plan:** https://claude.ai/code/artifact/64a6432f-5628-4671-a186-caa7fbe960f7

**M4 plan:** https://claude.ai/code/artifact/7031cc7e-46c0-4982-a1e3-8f8613890646

**Status:** M1–M3 complete and in daily use. Import and collections, bookmarks, the
thumbnail cache, `layout()` and the sheet, and the loop — randomize, select, pin,
remove, undo. Several settled decisions were reversed by using it; that is the point
of stopping here. The week of use is done and M4 is under way on branches: drag to
position, the lightbox, the All Photos rule, and the settings bar.

## What this is

**Photomancy** — divination by photograph. A **chance-operation instrument** for
finding photographic sequences: import photos, roll them into a grid, pin what
belongs, re-roll the rest, and move frames into place as a sequence forms. It also
prints.

Chance ordering is its reason for being, and that does not change. Randomness is the
method, not a starting point — this is aleatory practice (surrealist chance
operations), where serendipity is where sequences come from. Selection happens at
import; ordering is found by rolling.

**Editing follows from chance, and was always part of it.** Rolling produces
understanding of how the pictures fit together, and pinning is how the sequence found
that way is saved. Drag-pinning — putting a frame exactly where the sequence wants it —
is editorial and narrative intent by nature. There is nothing wrong with that, and it
does not undercut the chance method: it is what the rolls are for. **Never re-frame it
as a layout tool with a shuffle button** — the order is found by chance before it is
shaped by hand.

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
- **Fit is the only cell mode; Fill is not built.** Cropping is a decision that
  belongs to the photographer and is out of scope for this app, so there is no
  setting and no code path for it. Fit is the behaviour, not a preference.
- **Cell shape is a per-collection setting, derived from the collection by default.**
  The ratio shared by strictly more than half the photographs wins; where none holds
  a majority it falls back to square. That fallback is not a consolation — a mixed
  orientation collection has no majority ratio, and square is the only shape where a
  photograph and its transpose occupy the same area, so the arithmetic lands exactly
  where the minimax argument says it should. Options: derived, square, 3:2, 4:3.
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
  trivial. Watch the first fill, not memory. Measured at M2 on 80 photographs in one
  window: 6 cells 150 MB, 64 cells 145 MB, 120 cells 153 MB, 320 cells 143 MB — flat,
  as predicted.
- **The memory cache limit is a function of window area, not a constant.** Thumbnails
  are bucketed up to 1.5× their cell, and a cell's bucket is its long edge, so the
  decoded total is roughly two to four times the window's pixel count in bytes — a 5K
  window is 130–270 MB. The current fixed 256 MB happens to fit that and will not fit
  the next display. Derive it.
- **An empty cell is background and nothing else.** No outline, no placeholder, no
  hint that a cell is there — identical on screen and on paper. A grid that is not
  full should look like a grid that is not full.
- **The gap is the outer margin too.** One number everywhere: between cells and
  around the block. Cells flush against the window edge look wrong at a 1 px gap, and
  two numbers would make "padding, exact to the pixel" mean two things.
- **A derived cell shape re-derives on import.** It resolves live from whatever is in
  the collection now, so importing enough frames of another ratio does reshape the
  sheet. Accepted: the alternative is a frozen ratio nobody can see or explain, and a
  reshape at least corresponds to something the person just did.
- **The gap is pixels on screen and proportional on paper.** Printing scales the
  sheet uniformly, so a 12 px gap is not a fixed physical measure — it is
  `gap ÷ window width × page width`, and it changes with the window. Report the
  resulting millimetres in the print dialog instead of pretending otherwise.
- **Paper is the print target**, remembered per collection, starting at **A4
  landscape** — which makes the default output a contact sheet. It does not shape
  the screen; it is consulted only when scaling a sheet onto a page.
- **Collections, pins and the collection that was open survive a quit.** This is the
  point of the bookmarks and the store, and it is not negotiable. A pin records the
  photograph *and its cell*, so pinned frames return where they were left; the
  unpinned ones re-roll on launch, which is intended — if the order mattered, it
  should have been pinned. Restoring a full arrangement is explicitly not worth
  building.
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
- **Bookmarks are created with `.securityScopeAllowOnlyReadAccess`**, never
  `.withSecurityScope` alone. Without it the system asks for a read-*write* scoped
  bookmark, the kernel denies `file-write-data` against an app entitled only to read,
  and the call fails with Cocoa error 256 — *after* reading the file happily. Only the
  open panel exposed it: Open With and drag-and-drop hand over a read-write extension,
  the panel's Powerbox grant matches the entitlement and is read-only. When one import
  route fails and the others work, suspect the grant's mode, not the route.
- **Content hash** identifies a photo (survives renames) and keys the thumbnail cache.
- **Decode at display size** via ImageIO, off the main thread. Two-tier cache:
  in-memory `NSCache` + on-disk in Application Support.
- Collections are app-managed reference lists, **not folders**. Plain `Codable` store.
- **All Photos is the union of the collections**, and holds nothing of its own: every
  photograph in any collection, once, de-duped by content hash. It keeps its own pins
  and settings, because it is still a sheet to roll. A photograph enters the library
  only into a named collection — importing while All Photos is open creates a
  collection and opens it for naming — and leaves the library with its last collection:
  removing it from that collection takes it out (undoably), and deleting a collection
  takes the photographs no other collection holds. **The rule is structural, not a
  repair:** the library document's only public way in is adding photographs to a named
  collection, collections cannot be edited from outside it, and a randomized test checks
  after every step that the library equals the union. Deleting a collection clears the
  undo history, as deleting from the library does — otherwise undoing a removal of a
  photograph the deleted collection also held would restore a membership whose
  photograph had left the library.

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
| `P` | Pin/unpin the selected photo |
| Click | Select a photo |
| `⌘`Click | Add to / take out of the selection |
| `⇧`Click | Select from the last one chosen to here |
| `⌥`Click | Pin/unpin in place — leaves the selection alone |
| `⌫` | Remove selected from this collection — undoable |
| `⌘⌫` | Delete selected from Photomancy — not undoable |
| Double-click | Lightbox |
| `↩` | Open or close the lightbox |
| Drag | Move to a cell and pin there |
| `←` `→` | In lightbox: move through photos |
| `Esc` | Close lightbox |
| `⌘Z` / `⇧⌘Z` | Step through arrangements |
| `?` | Show the keyboard legend — `Esc` closes it |
| `⌘P` | Print (also yields PDF) |

- **A pin is marked with a white dot with a thin black outline, in the upper left
  corner of the frame.** One mark, one place, no variants.
- **The shortcuts get a legend, two ways.** Every action is a menu item showing its
  key equivalent, and every toolbar button's tooltip names its shortcut — the native
  baseline, which the menu bar needs anyway. Plus a `?` overlay over the sheet,
  dismissed with `Esc`, because the loop is a full-window activity and nobody is
  looking at the menu bar while they are in it.
- **The settings bar: typed numbers, a colour well, the shape beside the title.**
  Columns, rows and gap are whole-number fields, each with a stepper for the pointer;
  background is an opaque colour well whose choice is converted into sRGB, never
  reinterpreted; the tally sits at the right. Cell shape is a quiet menu beside the
  collection title, and a derived shape names what it resolved to — `Derived · 3:2`.
  The only limits are physical: no more gap, columns or rows than leave every cell at
  least a point in the current window, because past that the sheet goes blank.
- **Return opens and closes the lightbox** — the keyboard route the table lacked.
  `Space`, the Quick Look key, is Randomize.
- **Undo spans shuffles.** Non-negotiable — it's what makes gambling on chance safe.
- **Selection is a set, and Mac conventions decide it in one place.** Plain click
  replaces, `⌘` adds or removes one, `⇧` takes everything from the anchor to here.
  Branch on `NSEvent.modifierFlags` inside a single tap handler: a plain
  `onTapGesture` also fires for a modified click, so separate `.modifiers()`
  gestures would both run in an order that is not ours to choose.
- **`P` acts on the whole selection; a mixed selection pins rather than unpins.** The
  gesture should add the state being asked for, not take it from the frames that
  already have it.
- **Dragging a photograph onto a cell moves it there and pins it; the cells between
  shift one place.** A removal and an insertion composed — out of its cell, gap closed,
  back in at the target — so it follows the removal rule: pins travel with their
  photographs, nothing leaves the sheet, no cell empties that was not empty. Dragged
  back the run shifts right, dragged forward it shifts left. Onto an empty cell there
  is nothing to make room for, so it is simply placed. Dropped in the dead space or on
  its own cell, nothing is recorded. An ordinary step, so `⌘Z` undoes it.
- **Removing closes the gap, and pinned frames move up with everything else.** That
  settles what a pin means: it holds a photograph across *rolls*, not at a fixed cell
  for ever, so a pin's cell follows its photograph. Empty cells that were already
  there stay put; only the gap the removal made is closed.
- **The lightbox walks the sheet in cell order**, skipping empty cells. The sequence
  on the sheet is the one being divined; collection order is import order and means
  nothing here.
- **The lightbox never enlarges a photograph past its real size.** A small original is
  shown one file pixel to one display pixel, with background around it: stretching it
  would show it softer than the file is, and the lightbox is where a photographer looks
  closely. It decodes for the photograph's own drawn long edge, never past the
  original's — ImageIO does not enlarge, so a larger request only stores duplicates.
- **The lightbox names the file — essential, not bloat.** Reviewing a sequence often
  means choosing between near-identical frames, and the file's name is what tells them
  apart and what carries the decision out of the app, to wherever the frame is worked on
  next. Names are useful to have at hand in general. So the name sits centred below the
  photograph, following it, at the caption size of the bar's gap value, in a quiet ink
  derived from the sheet background so it reads on white and black alike. It does not
  reopen captions: nothing is written on the sheet or on paper.
- **`P` and the deletions work in the lightbox, on the photograph shown.** Same
  gesture, same meaning, everywhere.
- **Selection is model state, not focus.** A selected cell stays selected when the
  keyboard goes elsewhere. Tying the ring to `@FocusState` made it appear only while
  the mouse was down, which is not a selection — and Delete and the lightbox both act
  on it, so it has to outlast the click that made it.
- **Two deletions, named separately, neither hidden behind a dialog.**
  `Remove from Collection` (`⌫`) takes the photograph out of that list and **is
  undoable**; `Delete from Photomancy` (`⌘⌫`) takes it out of the library and **is
  not**, following Lightroom. A confirmation dialog was weighed and rejected: it
  degrades to a one-button dialog in All Photos, so the app would behave differently
  depending on where you stand.
- **At most ten removals stay reversible.** Ordinary steps are cheap — an arrangement
  is shared hashes — and stay 200 deep. A removal carries what it took away, so the
  stack is trimmed to the last ten of those, along with everything older, and undo
  never reaches a step that looks reversible and is not.
- **A removal's inverse is membership — and the reference only when it left the
  library.** Undoing restores ids, their *indices* in the ordered membership, and any
  pins — about a hundred bytes a photograph. A photograph that was in no other
  collection also left the library, so its `PhotoReference` travels in the step (about
  a kilobyte with its bookmark) and goes back at its index in the library, with its All
  Photos pins; the ten-removal bound caps what that holds. Measured
  alternative: a whole-document snapshot is 4.5 MB at 5,000 references, which is why
  it was rejected.
- **Deleting from the library clears the history.** The step is not undoable by
  decision, and leaving earlier steps in place would let `⌘Z` walk back into
  arrangements referring to a photograph that is gone.
- **Click selects; `⌥`click pins.** This reverses the brief's original inversion, and
  for a better reason than the one it replaced: selection is the prerequisite for
  everything else you can do to one photograph — open it in the lightbox, remove it —
  so the plainest gesture has to mean "this one", not "hold this one".
- **The pin mark is anchored to the cell, not to the photograph.** Following the frame
  is more literally correct, but every ratio put the dot somewhere else and the marks
  danced around the sheet. With a derived cell shape the two coincide for most frames.
- **Menu items carrying bare-key equivalents are disabled while a text field has the
  keyboard.** `Space` and `P` are matched before a field ever sees them, so without
  this nobody can type a space into a collection name.
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

Cut, copy, paste and select all — nothing responds to them, so they are removed from
the menu rather than left greyed out forever · watched folders · publishing to a server · constraint rules for the shuffle · editing
or cropping · **Fill / any crop-to-cell mode** · multi-page contact sheets ·
captions/metadata overlays on the sheet or on paper (the file's name in the lightbox is not one of these — see Interaction) · iCloud sync · soft proofing or CMYK · restoring a full
arrangement across launches.

Each sounds small and each moves this toward being a weaker Lightroom. If I propose
one, refuse and point here.

**The first release is lean and essential.** Nothing goes in because it would be nice
or because it is cheap. Features are added after release only on enough user requests
— that is the bar, and "enough" means more than one person asking unprompted.

## Working conventions

- Build and test from the shell (`xcodebuild`), not the Xcode GUI.
- **Use `/usr/bin/log`, never bare `log`** — `log` is a zsh builtin, so `log show`
  silently returns nothing from an interactive shell and every check that reads the
  app's diagnostics quietly passes for the wrong reason.
- **Push correctness into pure, testable functions** — `layout()`, hashing, cache keys.
  I can verify those alone with XCTest; I cannot inspect a running SwiftUI view the
  way I can a DOM. Thin views, tested logic.
- **End every exchange with `./Scripts/run.sh`** so there is always one thing to
  click to see the latest build. It quits any running copy first — `open` on a
  running app just fronts the old one, and testing a stale build wastes the trip.
- **Commits are save points, not hygiene.** Commit at every completed step without
  being asked, with a message in plain language, and say that the save point exists —
  do not assume it will be looked for. Work on a branch for a milestone or anything
  exploratory; merge to `main` once it is proven.
- **Name the undo path.** At the end of every feature and at every strategic decision,
  answer out loud: if this turns out wrong, how is it undone? Say which commit reverses
  it, say whether files on disk are involved — those do not revert when the code does —
  and flag one-way doors before walking through them.
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

Nothing open at present.
