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

    /// `nil` is All Photos — the virtual collection, and the first-launch view.
    var selection: UUID? {
        didSet {
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

    var columns: Int {
        get { settings.columns }
        set { updateSettings { $0.columns = max(1, newValue) } }
    }

    var rows: Int {
        get { settings.rows }
        set { updateSettings { $0.rows = max(1, newValue) } }
    }

    var gap: Double {
        get { settings.gap }
        set { updateSettings { $0.gap = max(0, newValue) } }
    }

    /// How many cells the current grid has, against how many photographs there
    /// are to put in them. Neither number constrains the other.
    var cellCount: Int { columns * rows }

    // MARK: - The loop

    private var history = History(Step(arrangement: Arrangement(), label: "Open"))

    /// The selected cells.
    ///
    /// Deliberately not tied to which view holds the keyboard. Selection is what
    /// Delete acts on, so it has to survive clicking elsewhere, and a ring that
    /// appears only while the mouse is down is not a selection.
    var selectedCells: Set<Int> = []

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
    func click(cell: Int, modifiers: NSEvent.ModifierFlags) {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)

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

    private func commit(_ arrangement: Arrangement, label: String, restoration: Restoration? = nil) {
        history.commit(Step(arrangement: arrangement, label: label, restoration: restoration))
        if restoration != nil {
            history.trimPast(toAtMost: Self.reversibleRemovals, matching: \.isRemoval)
        }
    }

    /// Space, and the toolbar button. The primary verb: it must cost nothing.
    func randomize() {
        let rolled = Arrangement.rolled(
            photographs: photographs,
            pins: arrangement.pins,
            cellCount: cellCount
        )
        stepping { commit(rolled, label: "Randomize") }
    }

    /// Option-click a photograph, or press P on the selected one.
    func togglePin(at cell: Int) {
        var next = arrangement
        next.togglePin(at: cell)
        guard next != arrangement else { return }
        commit(next, label: next.isPinned(cell: cell) ? "Pin" : "Unpin")
        persistPins()
    }

    /// Drag a photograph onto a cell: it moves there and is pinned, and the cells
    /// between shift one place to make room. An ordinary step, so ⌘Z puts the
    /// sheet back as it was.
    func move(from source: Int, to target: Int) {
        var next = arrangement
        next.move(from: source, to: target)
        guard next != arrangement else { return }
        stepping { commit(next, label: "Move") }
        // The selection is by cell, and the cells have just shifted under it.
        // What you dragged is what you were working with.
        select(target)
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

        let landing = selectedCells.min() ?? 0
        var next = arrangement
        next.removeClosingGaps(ids)
        refreshCellAspect()
        stepping { commit(next, label: ids.count == 1 ? "Remove" : "Remove \(ids.count)", restoration: restoration) }
        // The sheet has closed up, so the cell you were on now holds whatever
        // followed — which is where you would look next.
        selectedCells = next.photograph(at: landing) != nil ? [landing] : []
        selectionAnchor = selectedCells.first
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

    func undo() {
        var undone: Step?
        stepping { undone = history.undo() }
        guard let undone else { return }
        if let restoration = undone.restoration {
            store.restore(restoration)
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
        persistPins()
    }

    func moveSelection(byColumns columns: Int, rows: Int) {
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

    /// The sheet looks photographs up by hash on every frame, so a linear scan
    /// of the library would be a scan per cell per frame.
    private var referenceIndex: [ContentHash: PhotoReference] = [:]

    func reference(for id: ContentHash) -> PhotoReference? {
        referenceIndex[id]
    }

    func refreshCellAspect() {
        cellAspect = store.document.cellAspect(for: selection)
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
        let destination = selection
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
        store.removeCollection(selection)
        self.selection = nil
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
