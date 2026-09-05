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

    private var history = History(Arrangement())

    /// Focused cell for the keyboard route. Every action reachable by pointer is
    /// reachable from here too.
    var focusedCell: Int = 0

    /// The `?` overlay. Held here rather than in the view so the menu item and
    /// the key can be the same single route.
    var showingShortcuts = false

    /// Roughly 200 ms rather than a cut — the movement is what lets the eye
    /// register what changed, which is the whole point of animating at all.
    private func stepping(_ change: () -> Void) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            change()
        } else {
            withAnimation(.easeInOut(duration: 0.2), change)
        }
    }

    var arrangement: Arrangement { history.current }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    /// Space, and the toolbar button. The primary verb: it must cost nothing.
    func randomize() {
        let rolled = Arrangement.rolled(
            photographs: photographs,
            pins: arrangement.pins,
            cellCount: cellCount
        )
        stepping { history.commit(rolled) }
    }

    /// Click a photograph, or press P on the focused one.
    func togglePin(at cell: Int) {
        var next = arrangement
        next.togglePin(at: cell)
        guard next != arrangement else { return }
        history.commit(next)
        persistPins()
    }

    /// Releases everything and deals again.
    func reset() {
        let rolled = Arrangement.rolled(
            photographs: photographs,
            pins: [],
            cellCount: cellCount
        )
        stepping { history.commit(rolled) }
        persistPins()
    }

    func undo() {
        var stepped = false
        stepping { stepped = history.undo() }
        if stepped { persistPins() }
    }

    func redo() {
        var stepped = false
        stepping { stepped = history.redo() }
        if stepped { persistPins() }
    }

    func moveFocus(byColumns columns: Int, rows: Int) {
        guard cellCount > 0 else { return }
        let width = max(1, self.columns)
        let column = focusedCell % width
        let row = focusedCell / width
        let nextColumn = min(max(column + columns, 0), width - 1)
        let nextRow = min(max(row + rows, 0), max(0, (cellCount - 1) / width))
        focusedCell = min(nextRow * width + nextColumn, cellCount - 1)
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
            history.reset(to: fresh)
        } else {
            history.commit(fresh)
        }
        focusedCell = min(focusedCell, max(0, cellCount - 1))

        #if DEBUG
        let filled = history.current.slots.compactMap { $0 }.count
        log.notice("sheet: \(self.cellCount, privacy: .public) cells, \(filled, privacy: .public) filled, \(self.history.current.pinnedCells.count, privacy: .public) pinned, from \(self.photographs.count, privacy: .public) photographs")
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
