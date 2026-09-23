import Foundation
import os

/// The document, plus the file it lives in and the resolver that reads through
/// it. Owns persistence; owns nothing about presentation.
@MainActor
@Observable
public final class LibraryStore {

    public private(set) var document: LibraryDocument
    public let resolver: BookmarkResolver

    private let fileURL: URL
    private let log = Logger(subsystem: AppPaths.bundleIdentifier, category: "library")
    private var pendingSave: Task<Void, Never>?

    /// True once ``load()`` has run, so the first-launch empty state is not
    /// shown for the instant before the file is read.
    public private(set) var isLoaded = false

    /// Why the library on disk could not be read, while that is still the case.
    ///
    /// **While this is set, nothing is saved.** The document in memory is empty,
    /// and writing it would put an empty library over the only copy of the real
    /// one — a file from a newer build, or a damaged one, that may be perfectly
    /// recoverable. Found 2026-09-23: this guarantee had been documented since
    /// M3 and never built, and the save on quit did exactly that. It ends only
    /// when the person chooses to set the file aside; see
    /// ``setAsideUnreadableLibrary(at:)``.
    public private(set) var loadFailure: (any Error)?

    public init(fileURL: URL, resolver: BookmarkResolver = BookmarkResolver()) {
        self.fileURL = fileURL
        self.resolver = resolver
        self.document = LibraryDocument()
        wireBookmarkRefresh()
    }

    public convenience init() throws {
        self.init(fileURL: try AppPaths.libraryFile())
    }

    /// A bookmark that had to be recreated is worthless unless it is written
    /// back. This is the whole of `bookmarkDataIsStale` handling.
    private func wireBookmarkRefresh() {
        resolver.onBookmarkRefresh { [weak self] id, data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.document.updateBookmark(for: id, to: data)
                self.log.info("persisted refreshed bookmark for \(id.abbreviated, privacy: .public)")
                self.scheduleSave()
            }
        }
    }

    // MARK: - Persistence

    public func load() {
        defer { isLoaded = true }
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            log.info("no library file yet; starting empty")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            document = try JSONDecoder().decode(LibraryDocument.self, from: data)
            log.info("loaded \(self.document.references.count) references, \(self.document.collections.count) collections")
        } catch {
            // Refuse to overwrite something unreadable — a bad parse must not
            // become data loss on the next save.
            loadFailure = error
            log.error("could not read library, and will not write over it: \(String(describing: error), privacy: .public)")
        }
    }

    /// Moves a library that could not be read out of the way — kept, renamed,
    /// beside where it was — so a new one can be started and saved.
    ///
    /// The person's choice, never automatic: the file may be from a newer build,
    /// and then leaving it exactly where it is, for that build to open, is the
    /// right answer. Returns where it went, or `nil` when the library was
    /// readable and there is nothing to set aside.
    @discardableResult
    public func setAsideUnreadableLibrary(at date: Date = Date()) throws -> URL? {
        guard loadFailure != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let aside = fileURL.deletingLastPathComponent()
            .appendingPathComponent("library-unreadable-\(formatter.string(from: date)).json")
        try FileManager.default.moveItem(at: fileURL, to: aside)

        loadFailure = nil
        document = LibraryDocument()
        log.notice("unreadable library set aside as \(aside.lastPathComponent, privacy: .public)")
        return aside
    }

    public func saveNow() {
        guard loadFailure == nil else {
            log.error("not saving: the library on disk could not be read, and stays exactly as it is")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("could not save library: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Coalesce the writes that a bulk import produces.
    public func scheduleSave() {
        guard loadFailure == nil else { return }
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    // MARK: - Mutation

    /// Returns how many were new to the library. Duplicates are not an error —
    /// the same photograph arriving from a second path is one photograph, and it
    /// still joins this collection.
    ///
    /// Always into a named collection: All Photos is the union of the
    /// collections, so a photograph with no collection to go into is not added.
    @discardableResult
    public func add(_ references: [PhotoReference], to collectionID: UUID) -> Int {
        let added = document.add(references, to: collectionID)
        scheduleSave()
        return added
    }

    @discardableResult
    public func addCollection(named name: String) -> PhotoCollection {
        let collection = document.addCollection(named: name)
        scheduleSave()
        return collection
    }

    public func removeCollection(_ id: UUID) {
        for photo in document.removeCollection(id) { resolver.forget(photo) }
        scheduleSave()
    }

    /// Remembered so the app reopens where it was left. Not the arrangement —
    /// only which collection was on screen.
    public func setLastOpenedCollection(_ id: UUID?) {
        guard document.lastOpenedCollection != id else { return }
        document.lastOpenedCollection = id
        scheduleSave()
    }

    public func updateSettings(_ settings: SheetSettings, for collectionID: UUID?) {
        document.updateSettings(settings, for: collectionID)
        scheduleSave()
    }

    public func updatePins(_ pins: [Pin], for collectionID: UUID?) {
        document.updatePins(pins, for: collectionID)
        scheduleSave()
    }

    public func rename(_ id: UUID, to name: String) {
        document.renameCollection(id, to: name)
        scheduleSave()
    }

    @discardableResult
    public func removeFromCollection(_ ids: Set<ContentHash>, collectionID: UUID) -> Restoration? {
        let restoration = document.removeFromCollection(ids, collectionID: collectionID)
        if restoration != nil { scheduleSave() }
        return restoration
    }

    public func restore(_ restoration: Restoration) {
        document.restore(restoration)
        scheduleSave()
    }

    @discardableResult
    public func move(
        _ photographs: [ContentHash],
        pinned: Set<ContentHash>,
        from source: UUID?,
        to destination: UUID
    ) -> Transfer? {
        let transfer = document.move(photographs, pinned: pinned, from: source, to: destination)
        if transfer != nil { scheduleSave() }
        return transfer
    }

    public func reverse(_ transfer: Transfer) {
        document.reverse(transfer)
        scheduleSave()
    }

    public func remove(_ ids: Set<ContentHash>, from collectionID: UUID?) {
        if collectionID == nil {
            for id in ids { resolver.forget(id) }
        }
        document.remove(ids, from: collectionID)
        scheduleSave()
    }

    public func remove(_ ids: Set<ContentHash>) {
        for id in ids { resolver.forget(id) }
        document.remove(ids)
        scheduleSave()
    }

    // MARK: - Relink

    /// Point a photograph at a file that has moved.
    ///
    /// The resolver must forget the old path, and that is the whole reason this
    /// goes through the store rather than the document: a resolution is cached
    /// for the life of the process, so without this the app would keep reading
    /// through the URL that no longer works and the relink would appear to have
    /// done nothing until the next launch.
    @discardableResult
    public func relink(_ id: ContentHash, to url: URL) throws -> PhotoReference {
        let reference = try document.relink(id, to: url)
        resolver.forget(id)
        saveNow()
        return reference
    }

    /// Relink everything in a folder that a missing photograph turns out to be.
    ///
    /// Saved once at the end rather than per photograph. Returns what was
    /// relinked, and what could not be.
    @discardableResult
    public func relink(folderAt url: URL) -> (relinked: [PhotoReference], failed: [String]) {
        let missing = document.missingPhotographs(resolver: resolver)
        guard !missing.isEmpty else { return ([], []) }

        var relinked: [PhotoReference] = []
        var failed: [String] = []
        for found in Relink.search(folder: url, for: missing) {
            do {
                relinked.append(try document.relink(found.missing.id, to: found.url))
                resolver.forget(found.missing.id)
            } catch {
                failed.append(found.missing.displayName)
            }
        }
        if !relinked.isEmpty { saveNow() }
        return (relinked, failed)
    }

    public func missingPhotographs() -> [Relink.Missing] {
        document.missingPhotographs(resolver: resolver)
    }

    // MARK: - Reading

    public func photos(in collectionID: UUID?) -> [PhotoReference] {
        document.photos(in: collectionID)
    }
}
