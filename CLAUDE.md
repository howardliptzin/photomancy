# Photomancy — project contract

Native macOS app. **Sold on the Mac App Store** (signed, sandboxed) at a low price, and
**open source under MIT** on GitHub — see Distribution. SwiftUI, Swift 6, macOS 14+.

**Full brief (rationale lives there, not here):**
https://claude.ai/code/artifact/5917d4a2-04fb-4561-87ce-7844ceb530ba
Read it before writing code. Section numbers below refer to it.

**M2 plan:** https://claude.ai/code/artifact/64a6432f-5628-4671-a186-caa7fbe960f7

**M4 plan:** https://claude.ai/code/artifact/7031cc7e-46c0-4982-a1e3-8f8613890646

**M5 plan:** https://claude.ai/artifact/V66mrd8m3FsydyaBuFop4Z

**Status:** M1–M5 complete, merged to `main` and in daily use (M4 on 2026-09-15,
M5 print on 2026-09-22, relink the same day).
Import and collections, bookmarks, the thumbnail cache, `sheetGeometry()` and the sheet, the
loop — randomize, select, pin, remove, undo — then drag to position, the lightbox, All
Photos as the union of the collections, and the settings bar. After M4, found in use and
merged the same day: moving photographs between collections, by menu and by dragging
onto the sidebar. Using it reversed several settled decisions, which is why each
milestone stops for real use before the next. **M5, print and PDF, merged on
2026-09-22**: ⌘P and the print panel, Export PDF…, originals decoded at 360 ppi for
the paper finally chosen, and `Scripts/verify-print.sh`, which checks the printed PDF
against the window's own rectangles. Proven on paper — a sheet measured with a ruler
matches the millimetres the print dialog states. Still part of M5, on their own
branches: **relink** (§07), merged 2026-09-22 — strictly by content, a re-exported
edit is a different photograph — and, still to come and required before any beta,
deriving the memory cache limit from window area.

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

- **One pure `sheetGeometry()` function** returns the cells, the gap they were laid
  out at, and the block they occupy, from `(settings, cellAspect, canvas)` — over
  `layout()`, which still does the arithmetic. Screen positions views with the
  rectangles; print draws into a `CGContext` with the same ones. Geometry shared,
  drawing not. **Both callers go through `sheetGeometry()` and never `layout()`
  directly**, because it is what clamps the gap for a window too small for the stored
  one: called with the stored gap instead, print would lay out a sheet that is not the
  one on screen, in exactly that case.
- **The canvas is the window, not the page.** The sheet fills the window and
  reflows live as it is resized. Print does not recompute geometry: it takes the
  rectangles `sheetGeometry()` already produced for the window and applies one uniform
  scale-and-translate that fits the **grid block** — the cells and their outer gap —
  onto the page's printable rect. The window's dead space is not part of the
  composition and is not printed (settled 2026-09-19: at a wide window with square
  cells it made every photograph 59% smaller for nothing). Exact by construction
  rather than by discipline. Still one page, still no pagination, and no page breaks.
- **The flip lives inside `pageTransform`, and the transform is applied to the
  rectangles rather than concatenated into the context.** The screen's origin is at the
  top left and Quartz's at the bottom left, and a context drawing under that matrix
  renders every photograph upside down while every rectangle still lands exactly right.
  Mutation-tested on 2026-09-20: of eleven renderer tests, concatenating the transform
  is caught by *one* — the two-tone photograph — and inverting the flip's sign fails
  eight. Both tests earn their place.
- **The five isolation warnings in `SheetPrinting.swift` are accepted as they are.**
  Settled 2026-09-22. AppKit marks `NSPrintOperation` and `NSView` geometry `@MainActor`
  and then documents printing as happening on a thread of its own; both cannot be
  honoured, and the compiler says so five times. They are warnings rather than errors
  because AppKit is imported preconcurrency, and **no runtime check is inserted for
  them**. Do not "fix" them with `MainActor.assumeIsolated` — that *does* insert one, and
  brings back the crash step 0 measured. Everything avoidable was already moved off the
  printing thread by keeping the page size in the view's own locked state; what is left
  is irreducible, and the file says so where someone will read it. The cost accepted: an
  otherwise warning-clean build, so a new warning there needs looking at rather than
  assuming it is one of these.
- **An export fills the page; ⌘P fills the printer's imageable area.** An exported PDF
  has no printer, and baking in the margins of whichever one happened to be selected
  would make the same collection export differently on different machines. Both
  specifications stay reachable without a setting: ⌘P's own Save as PDF is the
  printer-margin route, and an exported PDF can be scaled at print time. Settled in use
  2026-09-21.
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
  where the minimax argument says it should. Options: Auto (derived), square, 3:2, 4:3.
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
- **Empty cells only ever trail.** Photographs fill from the first cell; an empty cell
  always means the collection ran out, never that something was parked past it. A roll
  fills from the front, a removal closes up, a drag re-inserts, and a pin held over from
  a larger grid is honoured and then closed up with its pin following it. Settled
  2026-09-20 and made total then: `Arrangement.emptiesOnlyTrail` asserts it, and a
  randomized test checks it after every operation. It is what makes a cell index mean a
  position in the sequence, which is what the drag rules below are written in terms of.
- **The gap is the outer margin too.** One number everywhere: between cells and
  around the block. Cells flush against the window edge look wrong at a 1 px gap, and
  two numbers would make "padding, exact to the pixel" mean two things.
- **A derived cell shape re-derives on import.** It resolves live from whatever is in
  the collection now, so importing enough frames of another ratio does reshape the
  sheet. Accepted: the alternative is a frozen ratio nobody can see or explain, and a
  reshape at least corresponds to something the person just did.
- **The gap is pixels on screen and proportional on paper.** Printing scales the
  sheet uniformly, so a 12 px gap is not a fixed physical measure — it is
  `gap ÷ block width × printed block width`, and it changes with the window. Report the
  resulting millimetres in the print dialog instead of pretending otherwise.
- **Paper is the print target**, remembered per collection, starting at **A4
  landscape** — which makes the default output a contact sheet. Whatever paper the
  print panel ends on is remembered, not only A4 and Letter, under new keys: the old
  `size` key stays readable so a reverted build still loads the library. It does not
  shape the screen; it is consulted only when scaling a sheet onto a page.
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
- **Print draws from the originals, decoded at the size they print: 360 pixels per
  inch, never past the original.** Never from the thumbnail cache, never from a
  camera's embedded preview — only a `.fullDecode`. The print panel's *preview* is a
  screen and draws thumbnails; only the output pass, for the paper finally chosen,
  decodes originals, off the main thread.
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
- **A photograph that has *moved* does not go missing — a *replaced* one does.**
  Measured 2026-09-22. Bookmarks resolve by file ID, so a file moved or renamed on the
  same volume is still found, at its new path, reported stale, and re-created and
  re-saved on the spot. What breaks a bookmark is a new inode with the same contents:
  restored from a backup, synced down by Dropbox or iCloud, re-downloaded, copied to
  another volume, exported over the top. **Relink is recovery from that, not a way to
  follow moves**, and it is usually wanted for a whole library at once — which is why
  the panel takes a folder as readily as a file. A test that only moves files is testing
  a path the app already handles and will find nothing missing; break one by copying it
  elsewhere, deleting the original, and clearing its thumbnails.
- **In the sandbox a bookmark whose target has gone resolves to Cocoa 259**,
  `NSFileReadCorruptFileError` — "isn't in the correct format" — and *not* to either
  no-such-file code, which is what an unsandboxed test process returns. Read as lost
  permission it sends someone to a privacy setting instead of to the file and disables
  Relink…. The mapping lives in `BookmarkResolver.resolutionFailure`, where it is tested.
- **A `PhotoReference` is a value, so a relink must reach every copy of it** — the
  document's, the resolver's cached URL, the controller's `referenceIndex`, and the
  cells' task keys. Miss one and the repair succeeds while the screen goes on showing
  the failure. And **a repair must never rebuild the arrangement**: that re-rolls the
  sheet, so the photograph landing in the mended cell is simply the wrong one.
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
`Scripts/verify-print.sh` is the standing regression for the print path and should be
run after anything that touches geometry, the transform or the renderer. It renders real
photographs, rasterises the PDF at 300 ppi and compares each photograph's edges with the
window's rectangles. Two numbers: *worst edge* is about 1.2 px on a correct render — pixel
quantisation plus Quartz's edge antialiasing, 0.11 mm at 300 ppi — and *stray*, ink
outside any photograph's rectangle, is the sharp one and is zero. Displacing every
photograph by half a point takes stray into the thousands. It needs no library and
destroys nothing.

**`verify-relaunch.sh` also deletes the app's whole library.** On a machine with real collections, copy
the container's `Data` folder out with `ditto` first and put it back afterwards. The
container's own `.com.apple.containermanagerd.metadata.plist` is protected by macOS —
it can be neither copied nor deleted, and the script's `rm` of the container fails on
it while still wiping `Data` — so `Data` is the unit to back up: it is everything the
app owns.

## Interaction — settled

Every core action has **both a pointer route and a keyboard route**. Neither is the
poor relation.

| | |
|---|---|
| `Space` | Randomize — **also a button in the control bar** |
| Arrow keys | Move the selection between cells |
| `P` | Pin/unpin the selected photo |
| Click | Select a photo |
| `⌘`Click | Add to / take out of the selection |
| `⇧`Click | Select from the last one chosen to here |
| `⌥`Click | Pin/unpin in place — leaves the selection alone |
| `⌫` | Remove selected from this collection — undoable |
| `⌘⌫` | Delete selected from Photomancy — not undoable |
| `⌃⌘N` | Move selected to a new collection — undoable |
| Edit ▸ Move to ▸, or right-click | Move selected to a collection (Add to ▸ in All Photos) |
| Double-click | Lightbox |
| `↩` | Open or close the lightbox |
| Drag | Move to a cell and pin there — the whole selection if it started on one |
| Drag onto the sidebar | Move to that collection — a new one on empty sidebar space |
| `←` `→` | In lightbox: move through photos |
| `Esc` | Close lightbox |
| `⌘Z` / `⇧⌘Z` | Step through arrangements |
| `⌘R` | Reset — release every pin and roll again |
| `⇧⌘R` | Rename the collection — or double-click it |
| `?` | Show the keyboard legend — `Esc` closes it |
| `⌘P` | Print (also yields PDF) |
| `⇧⌘E` | Export PDF… — the sheet to a file, filling the page |
| Sheet ▸ Relink… | Point a photograph the app cannot read at the file, or a folder at all of them — menu only, because a repair is not part of the loop |

- **A pin is marked with a white dot with a thin black outline, in the upper left
  corner of the frame.** One mark, one place, no variants.
- **A selection is ringed in the system accent** — the blue every Mac list and icon
  grid uses, at full opacity. Reversed 2026-09-20: a ring derived from the sheet
  background was elegant and, on the grey preset, invisible, and it has to read while a
  drag carries it. Unlike the pin mark, this is chrome and follows the platform.
- **The shortcuts get a legend, two ways.** Every action is a menu item showing its key
  equivalent, and every toolbar and control-bar button's tooltip names its shortcut —
  the native baseline, which the menu bar needs anyway. Plus a `?` overlay over the
  sheet, dismissed with `Esc`, because the loop is a full-window activity and nobody is
  looking at the menu bar while they are in it.
- **The control bar, left to right: grid, background, Randomize, tally.** Columns, rows
  and gap are whole-number fields, each with a stepper for the pointer. Background is
  three preset swatches — white, black, grey `#939292` — ringed when the sheet is on
  one, then a colour wheel for anything else. The wheel opens the Colors window, rings
  when the background is custom and shows that colour in its centre; a pick is converted
  into sRGB, never reinterpreted, and opaque. The system colour well was dropped: on a
  white bar it was an empty white capsule and did not read as a control. Then a
  **Randomize** button, the pointer route for `Space`: it moved out of the toolbar
  because it belongs with what shapes the sheet, and in the toolbar it was not where
  anyone looked. The tally sits at the right. Cell shape is a quiet menu beside the
  collection title, labelled **Auto** when the shape follows the photographs and naming
  what it resolved to — `Auto · 3:2`. The only limits are physical: no more gap, columns
  or rows than leave every cell at least a point in the current window, because past
  that the sheet goes blank.
- **Return opens and closes the lightbox** — the keyboard route the table lacked.
  `Space`, the Quick Look key, is Randomize.
- **Cut, Copy, Paste and Select All stay in the Edit menu.** Reversed: they were removed
  because "nothing responds to them", but every text field — collection names, the grid
  fields — does, and macOS delivers those keys only through the menu items. Without them
  the keys do nothing while typing. Likewise `⌘Z` belongs to the text while a field has
  the keyboard, and steps the sheet back only when none does.
- **Double-click a collection to rename it** — through the list's own primary action,
  never a tap gesture on the row. A tap gesture, even a simultaneous one, swallows the
  click the list selects with, and the sidebar stops changing collections.
- **Undo spans shuffles.** Non-negotiable — it's what makes gambling on chance safe.
- **Selection is a set, and Mac conventions decide it in one place.** Plain click
  replaces, `⌘` adds or removes one, `⇧` takes everything from the anchor to here.
  Branch on `NSEvent.modifierFlags` inside a single tap handler: a plain
  `onTapGesture` also fires for a modified click, so separate `.modifiers()`
  gestures would both run in an order that is not ours to choose.
- **`P` acts on the whole selection; a mixed selection pins rather than unpins.** The
  gesture should add the state being asked for, not take it from the frames that
  already have it.
- **Dragging onto a cell moves what is carried there and pins it; the cells between
  shift to make room.** A removal and an insertion composed — out of their cells, gaps
  closed, back in as one run starting at the cell dropped on — so it follows the removal
  rule: pins travel with their photographs, nothing leaves the sheet, and the count is
  conserved so no drop can push a photograph off the end. Dragged back the others shift
  right, dragged forward they shift left.
  - **A drag carries the whole selection when it started on a selected photograph**, and
    the run lands in sheet order with every frame in it pinned where it lands. Added
    2026-09-20, because every other action — `P`, `⌫`, `⌘⌫`, Move to ▸ — acts on the
    selection, and the drag acting on one was the only gesture that did not: same
    gesture, same meaning, everywhere. Moving a found run of three into place is the
    loop, not layout drift.
  - **Dropped past the last photograph it lands at the end of the sequence**, because
    empty cells only ever trail. Reversed 2026-09-20: a drop on an empty cell used to
    park the photograph there, which was the one gesture in the app that could open a
    hole in the middle of a sheet. Parking a frame out in the empty space is gone with
    it, and was not missed.
  - Dropped in the dead space beyond the grid, or where it already sits, nothing is
    recorded — a cancelled drag pins nothing. An ordinary step, so `⌘Z` undoes the whole
    run at once.
- **Removing closes the gap, and pinned frames move up with everything else.** That
  settles what a pin means: it holds a photograph across *rolls*, not at a fixed cell
  for ever, so a pin's cell follows its photograph. What is left keeps its order and
  closes up from the front — empty cells only ever trail.
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
- **Move to ▸ takes the selection into another collection, out of this one.** Found
  in use: rolling one collection shows that some of it belongs in another, and the
  only way there was importing again and removing. A submenu, not a dialog — the
  collections, with **New Collection** (`⌃⌘N`, Finder's New Folder with Selection) at
  the top, as Photos and Mail do. It sits in the **Edit** menu beside Remove from
  Collection, because both take photographs out of this collection and whoever looks
  for one finds the other; the Sheet menu is the loop itself. The same submenu is the
  right-click menu on a photograph, which acts on the clicked photograph alone when it
  is outside the selection, as in Finder. Disabled with nothing selected and while a
  text field has the keyboard.
  - **In All Photos it reads Add to ▸** and removes nothing — there is no source
    collection. Named collections only move; Add to there waits until someone reaches
    for it.
  - **One mutation in `LibraryDocument.move`.** The photographs join the destination
    before they leave the source. Done as remove-then-add, a photograph whose only
    collection is the source would pass through a moment outside the library and lose
    its All Photos pins. The randomized invariant test covers moves and their undo and
    redo, and `MoveTests` checks that undo and redo land exactly.
  - **Pins:** the source closes its gap as for a removal. The destination takes the
    photographs in sheet cell order, and the pinned ones stay pinned in its first
    cells not already pinned there, in that order — a found sequence carries across. A
    photograph already pinned in the destination keeps its cell there.
  - **After Move to New Collection the person stays on the sheet.** Switching mid-roll
    would lose it. The new collection waits in the sidebar with its name open.
  - **Undoable from the source sheet**: back at their indices with their pins, and out
    of the destination if the move put them there. A collection the move created stays,
    empty — deleting it is a separate decision. **Not counted against the ten
    removals**: nothing leaves the library, so the step holds ids, indices and pins,
    never a reference.
  - **Dragging out of the sheet onto the sidebar is the pointer route.** Within the
    sheet a drag still moves one photograph to a cell. Carried onto a collection row it
    moves there — the whole selection if the drag started on a selected photograph,
    otherwise just that one. Onto empty sidebar space, including the New Collection
    button, it goes into a new collection; onto All Photos or its own collection,
    nothing happens.
  - **A carried selection is seen leaving together** — found in use: with the rings
    hidden and only the dragged photograph moving, a drag of several read as dropping
    the selection, though all of it went. So the rings travel with their photographs,
    and **a drag of more than one gathers into a small stack under the pointer from the
    moment it starts**, in sheet order with the dragged one on top, with a Finder-style
    count travelling with it. Revised 2026-09-20: the stack used to form only once the
    pointer left the sheet, and until then a drag of several still read as a drag of
    one. The cost, accepted: inside the sheet a drop on a cell still moves only the
    dragged photograph, so the stack says what is being *carried*, not what a cell would
    take. The target row lights.
  - **After a drop you stay on the source sheet, as after the menu** — weighed in use on
    2026-09-15. Following the gesture felt natural, but opening a collection clears the
    undo history, so the move would arrive un-undoable; following is one click on the
    row just dropped on; and splitting a collection is usually several drops in a row.
    Revisit only if clicking the destination after nearly every drop becomes the habit
    — and then for the menu too, with undo made to survive the switch.
  - **The drop rule is `SidebarDrop.resolve` in Core.** Targets are measured through
    pass-through AppKit views (`DropZones`) when a drag asks — never a gesture on a row,
    never cached, so scrolling or collapsing the sidebar leaves nothing stale. The New
    Collection button has no zone: a reader inside the sidebar's bottom inset measures
    as the whole sidebar, which once made every drop a new collection.
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
  keyboard.** `Space`, `P`, `⌫` and `↩` are matched before a field ever sees them, so
  without this nobody could type a space into a collection name or delete a letter.
- **Randomize and Reset clear the selection.** A roll deals every unpinned photograph
  somewhere else, so a selection held by cell came back holding whatever happened to
  land there — which is nothing anyone chose. Found in use 2026-09-20. The lightbox
  follows the selection, so `Space` inside it closes it, which is correct: the
  photograph being looked at is no longer in that cell.
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
or cropping · **Fill / any crop-to-cell mode** · multi-page contact sheets ·
captions/metadata overlays on the sheet or on paper (the file's name in the lightbox
is not one of these — see Interaction) · iCloud sync · soft proofing or CMYK ·
restoring a full arrangement across launches.

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
- **Push correctness into pure, testable functions** — `sheetGeometry()`,
  `pageTransform()`, `SheetRenderer`, hashing, cache keys.
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

## Distribution — settled (2026-09-19)

- **v1 is sold on the Mac App Store, at a low price.** This reverses the original
  premise of a free app: the goal is to sell it. The price is set late in the beta,
  from what testers say; it lives in App Store Connect and can change at any time.
- **The code stays open source, MIT, on GitHub.** Good for how it is received, and a
  niche app runs little risk of someone selling a copy. Everything already pushed is
  MIT for good whatever happens later — that door is already walked through. Maccy and
  FSNotes sell MIT source on the Store this way: the Store copy is the same app,
  bought for convenience and to support the work.
- **The order:** finish M5 and the rest of the app — icon, sandbox audit, a verified
  Release build — then enrol in the Apple Developer Program, notarise, run a free beta,
  and put v1 on sale.
- **No beta before the app is complete, A to Z.** Testers judge the whole app, and a
  first impression is hard to redo. The cost is accepted: learning a milestone later
  whether the loop lands with other photographers.
- **The beta is free:** TestFlight with a public link, plus a notarised `.dmg` on GitHub
  Releases. Beta testers get v1 free. Testers come from Reddit — photobook and zine
  makers first — and photographers on Instagram.
- **Selling as an Italian freelancer with a Partita IVA,** under the individual
  enrolment below. Join the App Store Small Business Program before the first sale: 15%
  commission up to 1 million USD in proceeds per calendar year. The trader contact
  details the EU's Digital Services Act puts on the App Store page are accepted.

## Identity — settled

- **Bundle ID:** `com.luna-park.Photomancy`. Permanent once shipped.
- **App Store developer name:** `Howard Liptzin`. Individual enrollment — Luna Park is
  not a legal entity, and Apple only permits a trade name on an Organization account.
  Not revisitable: the developer name is fixed at first app-record creation.
- **luna-park.com** everywhere else: support and contact URLs, marketing URL, GitHub
  org, copyright string, About box.

## Unsettled — ask, don't assume

- **What happens to the free `.dmg` after the beta.** When a free build is as convenient
  as the Store copy, the Store becomes a tip jar: about 290,000 people run Maccy's free,
  self-updating build, while its $9.99 Store listing has too few ratings to show. FSNotes'
  free route is building from source. Decide before v1.
- **The price** — late in the beta.
