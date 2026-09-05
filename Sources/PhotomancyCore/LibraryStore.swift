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
            log.error("could not read library: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func saveNow() {
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
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    // MARK: - Mutation

    /// Returns how many were new. Duplicates are not an error — the same
    /// photograph arriving from a second path is one photograph.
    @discardableResult
    public func add(_ references: [PhotoReference], to collectionID: UUID?) -> Int {
        var added = 0
        for reference in references where document.insert(reference) { added += 1 }
        document.add(references.map(\.id), to: collectionID)
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
        document.removeCollection(id)
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
        guard let offset = document.collections.firstIndex(where: { $0.id == id }) else { return }
        document.collections[offset].name = name
        scheduleSave()
    }

    public func remove(_ ids: Set<ContentHash>) {
        for id in ids { resolver.forget(id) }
        document.remove(ids)
        scheduleSave()
    }

    // MARK: - Reading

    public func photos(in collectionID: UUID?) -> [PhotoReference] {
        document.photos(in: collectionID)
    }
}
