import SwiftUI
import AppKit
import os
import PhotomancyCore

/// The one piece of app-level state the views read. Everything it does is a
/// forward to Core; it holds no logic of its own, so the views above it can be
/// rebuilt without touching anything that is tested.
@MainActor
@Observable
final class LibraryController {

    static let shared = LibraryController()

    let store: LibraryStore
    let cache: ThumbnailCache

    /// `nil` is All Photos — the union of the collections, and the first-launch view.
    var selection: UUID? {
        didSet {
            showingLightbox = false
            refreshCellAspect()
            // Undo does not cross collections: stepping back into a sheet you
            // are no longer looking at would be a surprise, not a rescue.
            rebuildArrangement(resettingHistory: true)
            guard isRestored else { return }
            store.setLastOpenedCollection(selection)
        }
    }

    /// Set once the stored selection has been applied, so restoring it does not
    /// immediately write it back as if the person had chosen it.
    private var isRestored = false
    var importProgress: ImportProgress?
    var message: String?

    private let log = Logger(subsystem: AppPaths.bundleIdentifier, category: "controller")

    struct ImportProgress: Equatable {
        var completed: Int
        var total: Int
        var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
    }

    private init() {
        let locations = Self.locations()
        let store = LibraryStore(fileURL: locations.library)
        self.store = store
        self.cache = ThumbnailCache(resolver: store.resolver, directory: locations.thumbnails)
    }

    /// Falls back to a temporary directory if the container is not writable.
    /// Nothing will persist in that state, but the app should open rather than
    /// die on launch.
    private static func locations() -> (library: URL, thumbnails: URL) {
        if let library = try? AppPaths.libraryFile(),
           let thumbnails = try? AppPaths.thumbnailDirectory() {
            return (library, thumbnails)
        }
        let fallback = FileManager.default.temporaryDirectory
        return (fallback.appendingPathComponent("library.json"), fallback)
    }

    func start() {
        guard !store.isLoaded else { return }
        store.load()

        // Reopen on the collection that was on screen at quit. A collection that
        // has since been deleted falls back to All Photos rather than to nothing.
        let remembered = store.document.lastOpenedCollection
        selection = remembered.flatMap { id in
            store.document.collections.contains { $0.id == id } ? id : nil
        }
        isRestored = true
        refreshCellAspect()
        rebuildArrangement(resettingHistory: true)

        scanForMissingPhotographs()
        log.info("launched with \(self.store.document.references.count) references")
        #if DEBUG
        verifyAccessToEveryPhotograph()
        #endif
    }

    var photographs: [PhotoReference] {
        store.photos(in: selection)
    }

    var settings: SheetSettings {
        store.document.settings(for: selection)
    }

    /// Written straight through to the collection's stored settings, so the
    /// sheet a person leaves is the sheet they come back to.
    private func updateSettings(_ change: (inout SheetSettings) -> Void) {
        let cellsBefore = cellCount
        var settings = self.settings
        change(&settings)
        store.updateSettings(settings, for: selection)
        // Changing the gap leaves the sheet alone; changing the grid cannot,
        // because there is a different number of cells to fill.
        if cellCount != cellsBefore {
            rebuildArrangement(resettingHistory: false)
        }
    }

    /// The sheet's size, reported by the sheet. Used only to keep the grid
    /// controls inside what the window can physically show — past that,
    /// `layout()` has no room and the sheet goes blank. Never a policy bound.
    var canvas: CGSize = .zero

    var columns: Int {
        get { settings.columns }
        set { updateSettings { $0.columns = physicalCount(newValue, along: canvas.width) } }
    }

    var rows: Int {
        get { settings.rows }
        set { updateSettings { $0.rows = physicalCount(newValue, along: canvas.height) } }
    }

    /// Whole pixels, and no more than leaves every cell visible.
    var gap: Double {
        get { settings.gap }
        set {
            var gap = max(0, newValue.rounded())
            if canvas.width > 0, canvas.height > 0 {
                gap = min(gap, maximumGap(cols: columns, rows: rows, canvas: canvas))
            }
            updateSettings { $0.gap = gap }
        }
    }

    var background: SheetColor {
        get { settings.background }
        set { updateSettings { $0.backgroundHex = newValue.hex } }
    }

    var cellShape: CellShape {
        get { settings.cellShape }
        set {
            updateSettings { $0.cellShape = newValue }
            refreshCellAspect()
        }
    }

    var cellShapeTitle: String {
        settings.cellShape.menuTitle(derivedAspect: derivedAspect)
    }

    private func physicalCount(_ value: Int, along length: CGFloat) -> Int {
        let value = max(1, value)
        guard length > 0 else { return value }
        return min(value, maximumCells(along: Double(length), gap: settings.gap))
    }

    /// How many cells the current grid has, against how many photographs there
    /// are to put in them. Neither number constrains the other.
    var cellCount: Int { columns * rows }

    // MARK: - The loop

    private var history = History(Step(arrangement: Arrangement(), label: "Open")) {
        didSet { settleLightbox() }
    }

    /// The selected cells.
    ///
    /// Deliberately not tied to which view holds the keyboard. Selection is what
    /// Delete acts on, so it has to survive clicking elsewhere, and a ring that
    /// appears only while the mouse is down is not a selection.
    var selectedCells: Set<Int> = [] {
        didSet { settleLightbox() }
    }

    /// Where a Shift-click measures from — the last cell chosen outright.
    private var selectionAnchor: Int?

    var selectedReferences: [PhotoReference] {
        selectedCells.sorted().compactMap { cell in
            arrangement.photograph(at: cell).flatMap(reference(for:))
        }
    }

    var hasSelection: Bool { !selectedReferences.isEmpty }

    /// Mac conventions, decided in one place rather than by gesture precedence:
    /// plain replaces the selection, Command adds or removes one, Shift takes
    /// everything from the anchor to here. Option is the odd one out — it pins
    /// the photograph you hit and leaves the selection alone, because it is
    /// direct manipulation of that frame rather than a change of what is chosen.
    func click(cell: Int, modifiers: NSEvent.ModifierFlags, clickCount: Int = 1) {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)

        // A double-click is read here, from the click itself, rather than as a
        // second tap gesture. Stacking one would make SwiftUI hold every single
        // click for the double-click interval before selecting, and the loop
        // would lag at its most frequent gesture. The first click has already
        // selected; the second opens what it selected.
        if clickCount >= 2, flags.isDisjoint(with: [.command, .shift, .option]) {
            openLightbox(at: cell)
            return
        }
        if flags.contains(.option) {
            togglePin(at: cell)
            return
        }
        if flags.contains(.shift), let anchor = selectionAnchor {
            selectedCells = Set(min(anchor, cell)...max(anchor, cell))
            return
        }
        if flags.contains(.command) {
            if selectedCells.contains(cell) {
                selectedCells.remove(cell)
            } else {
                selectedCells.insert(cell)
            }
            selectionAnchor = cell
            return
        }
        select(cell)
    }

    func select(_ cell: Int) {
        selectedCells = [cell]
        selectionAnchor = cell
    }

    func select(_ cells: Set<Int>) {
        selectedCells = cells
        selectionAnchor = cells.min()
    }

    func clearSelection() {
        selectedCells = []
        selectionAnchor = nil
    }

    /// P acts on everything selected. Mixed selections pin rather than unpin —
    /// the gesture should add the state you are asking for, not take it away
    /// from the ones that already have it.
    func togglePinOnSelection() {
        let cells = selectedCells.sorted().filter { arrangement.photograph(at: $0) != nil }
        guard !cells.isEmpty else { return }
        let allPinned = cells.allSatisfy { arrangement.isPinned(cell: $0) }

        var next = arrangement
        for cell in cells { next.setPinned(!allPinned, at: cell) }
        guard next != arrangement else { return }
        commit(next, label: allPinned ? "Unpin" : "Pin")
        persistPins()
    }



    /// The `?` overlay. Held here rather than in the view so the menu item and
    /// the key can be the same single route.
    var showingShortcuts = false

    // MARK: - Lightbox

    /// Whether the lightbox is up. What it shows is not stored: it is the
    /// selected cell, so P, ⌫ and ⌘⌫ act on the photograph shown through the
    /// same menu items as on the sheet, with no second route to drift.
    var showingLightbox = false

    /// The cell being shown, or `nil` when the lightbox is closed or its cell no
    /// longer holds a photograph.
    var lightboxCell: Int? {
        guard showingLightbox, let cell = selectedCells.min(),
              arrangement.photograph(at: cell) != nil else { return nil }
        return cell
    }

    /// Double-click, or Return.
    func openLightbox(at cell: Int) {
        guard arrangement.photograph(at: cell) != nil else { return }
        select(cell)
        showingLightbox = true
    }

    func toggleLightbox() {
        if lightboxCell != nil {
            showingLightbox = false
        } else if let cell = selectedCells.min() {
            openLightbox(at: cell)
        }
    }

    func closeLightbox() {
        showingLightbox = false
    }

    /// Through the sheet in cell order, passing over empty cells and stopping at
    /// either end. The sequence on the sheet is the one being divined.
    func stepLightbox(_ step: Int) {
        guard let cell = lightboxCell,
              let next = arrangement.filledCell(from: cell, step: step) else { return }
        select(next)
    }

    /// Closes the lightbox once its cell holds nothing — after a deletion, an
    /// undo or a new grid — so it cannot spring open again on the next click.
    private func settleLightbox() {
        if showingLightbox, lightboxCell == nil { showingLightbox = false }
    }

    /// Which collection is being renamed inline, if any. Held here so the
    /// sidebar row and the menu command are the same one route.
    var renamingCollection: UUID?

    /// True while any text field has the keyboard.
    ///
    /// Randomize is Space and pinning is P — no modifiers — so those menu items
    /// would otherwise swallow every space and every p someone types into a
    /// name. A menu key equivalent is matched before the field ever sees the
    /// key, and disabling the item is the only thing that yields it back.
    var isEditingText = false

    func beginRenamingSelectedCollection() {
        guard let selection else { return }
        renamingCollection = selection
    }

    /// Roughly 200 ms rather than a cut — the movement is what lets the eye
    /// register what changed, which is the whole point of animating at all.
    func stepping(_ change: () -> Void) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            change()
        } else {
            withAnimation(.easeInOut(duration: 0.2), change)
        }
    }

    var arrangement: Arrangement { history.current.arrangement }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    /// Named steps, so the Edit menu reads "Undo Randomize" rather than "Undo".
    var undoTitle: String { history.pendingUndo.map { "Undo \($0.label)" } ?? "Undo" }
    var redoTitle: String { history.pendingRedo.map { "Redo \($0.label)" } ?? "Redo" }

    /// At most ten removals stay reversible. Ordinary steps are cheap and stay
    /// two hundred deep; a removal carries what it took away, and anything older
    /// than the tenth is dropped along with everything before it — so undo never
    /// reaches a step that looks reversible and is not.
    private static let reversibleRemovals = 10

    private func commit(
        _ arrangement: Arrangement,
        label: String,
        restoration: Restoration? = nil,
        transfer: Transfer? = nil
    ) {
        history.commit(Step(arrangement: arrangement, label: label, restoration: restoration, transfer: transfer))
        if restoration != nil {
            history.trimPast(toAtMost: Self.reversibleRemovals, matching: \.isRemoval)
        }
    }

    /// Space, and the Randomize button in the control bar. The primary verb: it
    /// must cost nothing.
    func randomize() {
        let rolled = Arrangement.rolled(
            photographs: photographs,
            pins: arrangement.pins,
            cellCount: cellCount
        )
        stepping { commit(rolled, label: "Randomize") }
        // A roll deals every unpinned photograph somewhere else, so a selection
        // by cell would come back holding whatever happened to land there —
        // which is not what anyone chose. Rolling starts from nothing selected.
        clearSelection()
    }

    /// Option-click a photograph, or press P on the selected one.
    func togglePin(at cell: Int) {
        var next = arrangement
        next.togglePin(at: cell)
        guard next != arrangement else { return }
        commit(next, label: next.isPinned(cell: cell) ? "Pin" : "Unpin")
        persistPins()
    }

    /// Drag onto a cell: what is carried moves there and is pinned, and the
    /// cells between shift to make room. A drag that started on a selected
    /// photograph carries the whole selection, as every other action does —
    /// they land as one run, in sheet order. An ordinary step, so ⌘Z puts the
    /// sheet back as it was.
    func move(from source: Int, to target: Int) {
        let carried = cellsCarried(from: source).sorted()
            .compactMap { arrangement.photograph(at: $0) }
        guard !carried.isEmpty else { return }

        var next = arrangement
        next.move(carried, to: target)
        guard next != arrangement else { return }
        stepping { commit(next, label: carried.count > 1 ? "Move Photographs" : "Move") }
        // The selection is by cell, and the cells have just shifted under it.
        // What you dragged is what you were working with, so it stays chosen —
        // at wherever it actually landed.
        let landed = carried.compactMap { photograph in
            next.slots.firstIndex(where: { $0 == photograph })
        }
        select(Set(landed))
        persistPins()
    }

    /// Releases everything and deals again.
    func reset() {
        let rolled = Arrangement.rolled(
            photographs: photographs,
            pins: [],
            cellCount: cellCount
        )
        stepping { commit(rolled, label: "Reset") }
        // A reset is a roll with every pin released, so it starts from nothing
        // selected for the same reason Randomize does.
        clearSelection()
        persistPins()
    }

    /// Takes the photograph out of this collection. Undoable — the reference is
    /// untouched, so putting it back is a matter of membership and pins.
    func removeSelectedFromCollection() {
        guard let collectionID = selection else { return }
        let ids = Set(selectedReferences.map(\.id))
        guard !ids.isEmpty else { return }
        guard let restoration = store.removeFromCollection(ids, collectionID: collectionID)
        else { return }

        var next = arrangement
        next.removeClosingGaps(ids)
        refreshCellAspect()
        settleSelection(after: next)
        stepping { commit(next, label: ids.count == 1 ? "Remove" : "Remove \(ids.count)", restoration: restoration) }
        persistPins()
    }

    /// Takes the photograph out of the library entirely. Not undoable, by
    /// decision — so the history is cleared rather than left holding steps that
    /// refer to a photograph no longer there. The file on disk is untouched;
    /// re-importing is the way back.
    func deleteSelectedFromLibrary() {
        let ids = Set(selectedReferences.map(\.id))
        guard !ids.isEmpty else { return }
        store.remove(ids, from: nil)
        selectedCells = []
        selectionAnchor = nil
        refreshCellAspect()
        rebuildArrangement(resettingHistory: true)
    }

    // MARK: - Moving to another collection

    /// Where the selection can go: every collection but the one on screen.
    var moveDestinations: [PhotoCollection] {
        store.document.collections.filter { $0.id != selection }
    }

    /// All Photos holds nothing of its own, so from there photographs are added
    /// to a collection and nothing is taken out.
    var moveMenuTitle: String { selection == nil ? "Add to" : "Move to" }

    /// A right-click or a drag that starts on a photograph outside the selection
    /// acts on that photograph alone, as in Finder; inside it, on the whole
    /// selection.
    func target(from cell: Int) {
        guard !selectedCells.contains(cell) else { return }
        select(cell)
    }

    func cellsCarried(from cell: Int) -> Set<Int> {
        selectedCells.contains(cell) ? selectedCells : [cell]
    }

    // MARK: - Dragging out of the sheet

    /// Measures the sidebar's targets when a drag asks. Not observed: frames
    /// change on every layout pass and nothing draws from them.
    @ObservationIgnored let dropZones = DropZones()

    /// Where photographs dragged out of the sheet would go if dropped now. The
    /// sidebar highlights it; the sheet gathers what would leave under the pointer.
    var sidebarDrop: SidebarDrop?

    /// Dropped on the sidebar: the same moves the menus make, so undo and the
    /// rules for pins are identical whichever route was taken.
    func drop(from cell: Int, on drop: SidebarDrop) {
        switch drop {
        case .collection(let destination):
            target(from: cell)
            moveSelectedPhotographs(to: destination)
        case .newCollection:
            target(from: cell)
            moveSelectedPhotographsToNewCollection()
        case .refused:
            break
        }
    }

    /// Moves the selected photographs into another collection, out of this one.
    ///
    /// They join in sheet cell order, and the pinned ones stay pinned in the
    /// destination's first free cells in that order, so a found sequence carries
    /// across. Here the gap closes as it does for a removal. Undoable like a
    /// removal, but not counted against the ten: nothing leaves the library, so
    /// the step holds no reference.
    func moveSelectedPhotographs(to destination: UUID) {
        let cells = selectedCells.sorted().filter { arrangement.photograph(at: $0) != nil }
        let photographs = cells.compactMap { arrangement.photograph(at: $0) }
        guard !photographs.isEmpty else { return }
        let pinned = Set(cells.filter { arrangement.isPinned(cell: $0) }.compactMap { arrangement.photograph(at: $0) })
        guard let transfer = store.move(photographs, pinned: pinned, from: selection, to: destination)
        else { return }

        var next = arrangement
        if transfer.removal != nil {
            next.removeClosingGaps(Set(photographs))
            settleSelection(after: next)
        }
        refreshCellAspect()
        let verb = transfer.removal == nil ? "Add" : "Move"
        let label = photographs.count == 1 ? verb : "\(verb) \(photographs.count)"
        stepping { commit(next, label: label, transfer: transfer) }
        persistPins()
    }

    /// ⌃⌘N. The person stays on this sheet — switching mid-roll would lose the
    /// sheet they are working on — and the new collection waits in the sidebar
    /// with its name ready to type.
    func moveSelectedPhotographsToNewCollection() {
        guard hasSelection else { return }
        let collection = store.addCollection(named: "Collection \(store.document.collections.count + 1)")
        moveSelectedPhotographs(to: collection.id)
        renamingCollection = collection.id
    }

    /// After photographs leave the sheet and it closes up, the cell you were on
    /// holds whatever followed — which is where you would look next. In the
    /// lightbox, taking the last photograph on the sheet steps back to the one
    /// before rather than closing. Chosen before the commit, so the lightbox
    /// never sees a moment with nothing to show.
    private func settleSelection(after next: Arrangement) {
        let landing = selectedCells.min() ?? 0
        if next.photograph(at: landing) != nil {
            selectedCells = [landing]
        } else if showingLightbox, let previous = next.filledCell(from: landing, step: -1) {
            selectedCells = [previous]
        } else {
            selectedCells = []
        }
        selectionAnchor = selectedCells.first
    }

    func undo() {
        var undone: Step?
        stepping { undone = history.undo() }
        guard let undone else { return }
        if let restoration = undone.restoration {
            store.restore(restoration)
            refreshCellAspect()
        }
        if let transfer = undone.transfer {
            // A collection the move created stays in the sidebar, empty.
            store.reverse(transfer)
            refreshCellAspect()
        }
        persistPins()
    }

    func redo() {
        var redone: Step?
        stepping { redone = history.redo() }
        guard let redone else { return }
        if let restoration = redone.restoration {
            store.removeFromCollection(
                Set(restoration.memberships.map(\.photo)),
                collectionID: restoration.collection
            )
            refreshCellAspect()
        }
        if let transfer = redone.transfer {
            store.move(
                transfer.photographs,
                pinned: Set(transfer.pinned),
                from: transfer.source,
                to: transfer.destination
            )
            refreshCellAspect()
        }
        persistPins()
    }

    func moveSelection(byColumns columns: Int, rows: Int) {
        if showingLightbox {
            // ← → walk the sheet; a sequence has no up or down.
            if columns != 0 { stepLightbox(columns) }
            return
        }
        guard cellCount > 0 else { return }
        guard let current = selectedCells.min(), selectedCells.count == 1 else {
            // From nothing, or from a multiple selection, an arrow key settles
            // on one cell rather than trying to move a set.
            select(selectedCells.min() ?? 0)
            return
        }
        let width = max(1, self.columns)
        let column = current % width
        let row = current / width
        let nextColumn = min(max(column + columns, 0), width - 1)
        let nextRow = min(max(row + rows, 0), max(0, (cellCount - 1) / width))
        select(min(nextRow * width + nextColumn, cellCount - 1))
    }

    /// Deals a fresh sheet honouring whatever is pinned.
    ///
    /// `resettingHistory` is for changes that are not a step the person took —
    /// opening a collection, or an import — where an undo would step into
    /// something they never did.
    func rebuildArrangement(resettingHistory: Bool) {
        let fresh = Arrangement.rolled(
            photographs: photographs,
            pins: store.document.pins(in: selection),
            cellCount: cellCount
        )
        if resettingHistory {
            history.reset(to: Step(arrangement: fresh, label: "Open"))
        } else {
            commit(fresh, label: "Grid")
        }
        selectedCells = selectedCells.filter { $0 < cellCount }

        #if DEBUG
        let filled = history.current.arrangement.slots.compactMap { $0 }.count
        log.notice("sheet: \(self.cellCount, privacy: .public) cells, \(filled, privacy: .public) filled, \(self.history.current.arrangement.pinnedCells.count, privacy: .public) pinned, from \(self.photographs.count, privacy: .public) photographs")
        #endif
    }

    /// Pins persist; arrangements do not. A photograph whose position mattered
    /// should have been pinned.
    private func persistPins() {
        store.updatePins(arrangement.pins, for: selection)
    }

    /// Cached rather than resolved per frame.
    ///
    /// A derived cell shape clusters every ratio in the collection, and the
    /// sheet re-lays out on every resize tick — recomputing there would walk the
    /// whole library dozens of times a second. Recomputed when the collection
    /// changes and when photographs arrive, which is exactly the settled
    /// behaviour: a derived shape re-derives on import.
    private(set) var cellAspect: Double = 1

    /// What a derived shape resolves to for this collection, whichever shape is
    /// chosen — the menu names it. Cached for the same reason as `cellAspect`.
    private(set) var derivedAspect: Double = 1

    /// The sheet looks photographs up by hash on every frame, so a linear scan
    /// of the library would be a scan per cell per frame.
    private var referenceIndex: [ContentHash: PhotoReference] = [:]

    func reference(for id: ContentHash) -> PhotoReference? {
        referenceIndex[id]
    }

    func refreshCellAspect() {
        cellAspect = store.document.cellAspect(for: selection)
        derivedAspect = CellShape.derivedFromCollection.aspect(for: store.photos(in: selection))
        referenceIndex = Dictionary(
            store.document.references.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var currentTitle: String {
        guard let selection,
              let collection = store.document.collections.first(where: { $0.id == selection })
        else { return "All Photos" }
        return collection.name
    }

    // MARK: - Import

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.message = "Choose photographs, or a folder of photographs."
        panel.prompt = "Import"
        guard panel.runModal() == .OK else { return }
        importPhotographs(from: panel.urls)
    }

    func importPhotographs(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        // All Photos is the union of the collections and holds nothing of its
        // own. Photographs arriving there — dropped on the window, opened with
        // Photomancy, or on first launch — go into a new collection, opened with
        // its name ready to type.
        if selection == nil {
            newCollection()
            renamingCollection = selection
        }
        guard let destination = selection else { return }
        importProgress = ImportProgress(completed: 0, total: 0)

        Task {
            let result = await Importer.makeReferences(for: urls) { completed, total in
                Task { @MainActor in
                    self.importProgress = ImportProgress(completed: completed, total: total)
                }
            }
            let added = store.add(result.references, to: destination)
            store.saveNow()
            refreshCellAspect()
            // Not undoable: stepping back would not un-import the photographs,
            // so offering it would be a lie.
            rebuildArrangement(resettingHistory: true)
            importProgress = nil

            let duplicates = result.references.count - added
            var parts: [String] = []
            if added > 0 { parts.append("Imported \(added) \(added == 1 ? "photograph" : "photographs").") }
            if duplicates > 0 { parts.append("\(duplicates) already in the library.") }
            if !result.failures.isEmpty { parts.append("\(result.failures.count) could not be read.") }
            if result.scanned == 0 { parts.append("Nothing there Photomancy can read.") }
            message = parts.joined(separator: " ")

            log.info("import: scanned \(result.scanned), added \(added), duplicates \(duplicates), failed \(result.failures.count)")
        }
    }

    // MARK: - Collections

    func newCollection() {
        let existing = store.document.collections.count
        let collection = store.addCollection(named: "Collection \(existing + 1)")
        selection = collection.id
    }

    func deleteSelectedCollection() {
        guard let selection else { return }
        deleteCollection(selection)
    }

    /// Photographs in no other collection leave the library with it — All Photos
    /// is the union of the collections. Not undoable, like deleting from the
    /// library, so the history is cleared, and a sheet that was showing them is
    /// dealt afresh.
    func deleteCollection(_ id: UUID) {
        store.removeCollection(id)
        refreshCellAspect()
        if selection == id {
            selection = nil
        } else if selection == nil {
            rebuildArrangement(resettingHistory: true)
        } else {
            // This sheet is unchanged, but its undo steps are not safe: undoing a
            // removal of a photograph the deleted collection also held would put
            // back a membership whose photograph has left the library.
            history.reset(to: history.current)
        }
    }

    // MARK: - Relink

    /// Photographs the app has tried to read and could not find.
    ///
    /// Populated by the cells as they fail, which is the same event that draws
    /// the triangle — so what is marked on the sheet and what Relink… will act
    /// on cannot disagree.
    private(set) var missingPhotographs: Set<ContentHash> = []

    func noteMissing(_ id: ContentHash) { missingPhotographs.insert(id) }

    /// Ask the whole library what it cannot read.
    ///
    /// The cells report what they try to draw, which is not enough on its own:
    /// a roll deals a subset, so a collection with more photographs than cells
    /// can hold a missing one that never appears on screen — and Relink… would
    /// be disabled while the library was quietly short a photograph. Being
    /// missing is a fact about the library, not about the current sheet, so it
    /// is asked of the library. A `stat` each, off the main thread, on launch
    /// and after every relink.
    func scanForMissingPhotographs() {
        let store = self.store
        Task.detached(priority: .utility) {
            let missing = await MainActor.run { store.missingPhotographs() }
            await MainActor.run { [weak self] in
                guard let self else { return }
                let found = Set(missing.map(\.id))
                guard found != self.missingPhotographs else { return }
                self.missingPhotographs = found
                if !found.isEmpty {
                    self.log.notice("\(found.count, privacy: .public) photographs cannot be read — Relink… is available")
                }
            }
        }
    }

    func noteFound(_ id: ContentHash) {
        guard missingPhotographs.contains(id) else { return }
        missingPhotographs.remove(id)
    }

    /// Whether Relink… has anything to act on: a selected photograph that is
    /// missing, or any missing photograph at all when nothing is selected.
    var canRelink: Bool {
        !missingPhotographs.isEmpty && !isEditingText
    }

    /// The missing photograph the menu will offer to relink — the selected one
    /// if a selected one is missing, otherwise the first on the sheet.
    private var relinkTarget: PhotoReference? {
        let selected = selectedCells
            .compactMap { arrangement.photograph(at: $0) }
            .first { missingPhotographs.contains($0) }
        let id = selected ?? arrangement.slots.compactMap { $0 }.first { missingPhotographs.contains($0) }
        return id.flatMap { reference(for: $0) }
    }

    /// Sheet ▸ Relink… — point a photograph at the file, or a folder at all of
    /// them.
    ///
    /// One panel that takes either. Choosing the file itself is the precise
    /// answer for one photograph; choosing the folder it now lives in fixes
    /// every photograph that turns out to be in there, which is the common case
    /// — a library restored from a backup loses them all at once, not one at a
    /// time.
    func presentRelinkPanel() {
        guard let target = relinkTarget else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image, .folder]
        panel.message = "Find “\(target.displayName)”, or choose the folder its photographs are in now."
        panel.prompt = "Relink"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isFolder {
            relinkFolder(url)
        } else {
            relinkOne(target, to: url)
        }
    }

    private func relinkOne(_ target: PhotoReference, to url: URL) {
        do {
            let relinked = try store.relink(target.id, to: url)
            missingPhotographs.remove(target.id)
            log.notice("relink: \(relinked.displayName, privacy: .public) found again")
            refreshAfterRelink()
            report("“\(relinked.displayName)” was found again.")
        } catch {
            present(error)
        }
    }

    private func report(_ message: String, detail: String? = nil) {
        let alert = NSAlert()
        alert.messageText = message
        if let detail { alert.informativeText = detail }
        alert.alertStyle = .informational
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func relinkFolder(_ url: URL) {
        let result = store.relink(folderAt: url)
        for reference in result.relinked { missingPhotographs.remove(reference.id) }
        log.notice("relink: \(result.relinked.count, privacy: .public) found in \(url.lastPathComponent, privacy: .public)")

        if result.relinked.isEmpty {
            report(
                "Nothing in “\(url.lastPathComponent)” matches a missing photograph.",
                detail: "Relinking matches a file's contents exactly, so an edited or "
                    + "re-exported copy counts as a different photograph."
            )
            return
        }
        refreshAfterRelink()
        // The sheet is not re-rolled, so a relinked photograph that was not
        // dealt shows no change at all — without this, fixing nine of them
        // looks identical to fixing none.
        let names = result.relinked.map(\.displayName).sorted()
        report(
            names.count == 1
                ? "“\(names[0])” was found again."
                : "\(names.count) photographs were found again.",
            detail: names.count == 1 ? nil : names.prefix(6).joined(separator: ", ")
                + (names.count > 6 ? ", and \(names.count - 6) more." : ".")
        )
    }

    /// Bumped by a relink, so the cells look again.
    ///
    /// A relinked photograph keeps its id — identity is its content, and its
    /// content did not change — so nothing a cell keys on has changed and the
    /// triangle would sit there over a photograph that is now perfectly
    /// readable. This is what tells them to re-read.
    private(set) var relinkGeneration = 0

    /// A repair, and nothing more.
    ///
    /// Emphatically **not** a rebuild of the arrangement. Rebuilding re-rolls,
    /// and found in use 2026-09-22: relinking in All Photos dealt a fresh
    /// subset of 205 photographs into 16 cells, so the cell that had been
    /// showing the triangle came back holding some other photograph and the
    /// repair looked like it had put the wrong picture there. Rolling is
    /// `Space` and `⌘R`; nothing else may do it behind your back.
    private func refreshAfterRelink() {
        relinkGeneration += 1
        scanForMissingPhotographs()
    }

    // MARK: - Printing

    /// Whether ⌘P has anything to do. An empty sheet is not worth a panel.
    var canPrint: Bool {
        !arrangement.slots.compactMap { $0 }.isEmpty
    }

    /// File ▸ Print… — the panel, on this collection's paper.
    ///
    /// Async because everything the job needs is gathered *before* the panel
    /// opens: whether every original can still be read, and a thumbnail for
    /// each placed photograph. Both are fast — the thumbnails are the ones on
    /// screen — and doing them here is what keeps the panel itself instant.
    /// Decoding originals happens later, in the output pass, on the thread
    /// AppKit spawns for it.
    func printSheet() async {
        guard let job = buildPrintJob() else { return }

        // Asked now rather than when the job runs: a missing photograph is a
        // thing to go and fix, and finding out after choosing paper and
        // pressing Print is finding out too late.
        do {
            try PrintImages.checkAvailable(job.placements, resolver: store.resolver)
        } catch {
            present(error)
            return
        }
        run(await withPreviewFrames(job))
    }

    /// Everything one job needs, gathered on the main thread. Shared by ⌘P and
    /// Export PDF… so the two cannot drift into printing different sheets.
    private func buildPrintJob() -> SheetPrintJob? {
        let geometry = sheetGeometry(settings: settings, cellAspect: cellAspect, canvas: canvas)
        guard !geometry.cells.isEmpty else { return nil }

        var placements: [PrintImages.Placement] = []
        for (cell, id) in arrangement.slots.prefix(geometry.cells.count).enumerated() {
            guard let id, let reference = reference(for: id) else { continue }
            placements.append(PrintImages.Placement(cell: cell, reference: reference))
        }
        guard !placements.isEmpty else { return nil }

        return SheetPrintJob(
            geometry: geometry,
            background: settings.background,
            placements: placements,
            previewFrames: [],
            resolver: store.resolver,
            title: currentTitle
        )
    }

    /// Thumbnails for the print panel's preview. Export needs none — it has no
    /// preview, and everything it draws is decoded from the originals.
    private func withPreviewFrames(_ job: SheetPrintJob) async -> SheetPrintJob {
        var frames: [SheetRenderer.Frame] = []
        for placement in job.placements {
            let cell = job.geometry.cells[placement.cell]
            let pixels = ThumbnailSize.bucket(forCell: cell.size, scale: 2)
            if let thumbnail = try? await cache.thumbnail(for: placement.reference, maxPixel: pixels) {
                frames.append(SheetRenderer.Frame(cell: placement.cell, image: thumbnail.image))
            }
        }
        return SheetPrintJob(
            geometry: job.geometry, background: job.background,
            placements: job.placements, previewFrames: frames,
            resolver: job.resolver, title: job.title
        )
    }

    private func run(_ job: SheetPrintJob) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        settings.paper.apply(to: info)
        // The view is sized to the imageable area and draws into all of it, so
        // nothing must scale or centre it a second time.
        info.leftMargin = 0
        info.rightMargin = 0
        info.topMargin = 0
        info.bottomMargin = 0
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        let view = PrintedSheetView(job: job, imageable: info.imageablePageBounds.size)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.canSpawnSeparateThread = true
        operation.jobTitle = job.title
        operation.printPanel.options.insert([.showsPaperSize, .showsOrientation, .showsPreview])
        operation.printPanel.addAccessoryController(PrintMetricsAccessory(geometry: job.geometry))

        let collection = selection
        SheetPrintDelegate.shared.didFinish = { [weak self] operation, success in
            guard let self else { return }
            // Whatever paper the panel ended on is what this collection prints
            // on next time — remembered under keys an older build ignores.
            if success {
                var settings = self.store.document.settings(for: collection)
                settings.paper = Paper(printInfo: operation.printInfo)
                self.store.updateSettings(settings, for: collection)
            }
            if let error = view.error { self.present(error) }
        }

        guard let window = NSApp.keyWindow else {
            _ = operation.run()
            return
        }
        operation.runModal(
            for: window,
            delegate: SheetPrintDelegate.shared,
            didRun: #selector(SheetPrintDelegate.printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }

    /// File ▸ Export PDF… — the same renderer and the same images as ⌘P, to a
    /// file instead of a printer.
    ///
    /// In scope because the read-write entitlement is already spent: step 0
    /// found that the print panel's own Save as PDF does not work without it,
    /// so the cost of this command was paid before it was written.
    func exportPDF() async {
        guard let job = buildPrintJob() else { return }

        do {
            try PrintImages.checkAvailable(job.placements, resolver: store.resolver)
        } catch {
            present(error)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(job.title).pdf"
        panel.message = "Export this sheet as a PDF."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let paper = settings.paper
        do {
            // Decoding originals is the slow part — about a second for twenty
            // photographs — and it has no business on the main thread just
            // because there is no print operation to spawn one this time.
            let data = try await Task.detached(priority: .userInitiated) { () -> Data in
                let page = CGRect(origin: .zero, size: paper.points)
                let frames = try PrintImages.frames(
                    for: job.placements,
                    geometry: job.geometry,
                    printable: page,
                    resolver: job.resolver
                )
                let renderer = SheetRenderer(
                    geometry: job.geometry, background: job.background, frames: frames
                )
                guard let data = renderer.pdf(pageSize: paper.points, title: job.title) else {
                    throw PhotoAccessError.decodeFailed(name: job.title)
                }
                return data
            }.value

            try data.write(to: url)
            log.notice("export: wrote \(data.count, privacy: .public) bytes to \(url.lastPathComponent, privacy: .public)")
        } catch {
            present(error)
        }
    }

    private func present(_ error: any Error) {
        log.error("print: \(error.localizedDescription, privacy: .public)")
        let alert = NSAlert()
        alert.messageText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if let suggestion = (error as? LocalizedError)?.recoverySuggestion {
            alert.informativeText = suggestion
        }
        alert.alertStyle = .warning
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Diagnostics

    /// Redeems every bookmark and reads the header of every file.
    ///
    /// This is the check that matters on a second launch: it goes through the
    /// resolver and touches the originals, so it cannot be satisfied by a warm
    /// thumbnail cache. Debug builds only.
    private func verifyAccessToEveryPhotograph() {
        let references = store.document.references
        guard !references.isEmpty else { return }
        let resolver = store.resolver
        let log = self.log

        Task.detached(priority: .utility) {
            var ok = 0
            var failed: [String] = []
            for reference in references {
                do {
                    _ = try resolver.withAccess(reference) { url in
                        try ThumbnailDecoder.probe(url: url)
                    }
                    ok += 1
                } catch {
                    failed.append("\(reference.displayName): \(error.localizedDescription)")
                }
            }
            log.notice("access check: \(ok, privacy: .public) of \(references.count, privacy: .public) photographs opened through their bookmarks")
            for failure in failed {
                log.error("access check failed — \(failure, privacy: .public)")
            }
        }
    }

    func logCacheSummary() {
        let stats = cache.statistics
        log.notice("thumbnails: \(stats.memoryHits, privacy: .public) from memory, \(stats.diskHits, privacy: .public) from disk cache, \(stats.decodes, privacy: .public) decoded from originals, \(stats.failures, privacy: .public) failed")
    }
}
