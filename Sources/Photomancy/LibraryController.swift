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
    var selection: UUID?
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
        log.info("launched with \(self.store.document.references.count) references")
        #if DEBUG
        verifyAccessToEveryPhotograph()
        #endif
    }

    var photographs: [PhotoReference] {
        store.photos(in: selection)
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
