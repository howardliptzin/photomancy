import Foundation
import UniformTypeIdentifiers
import os

/// Turning URLs the person chose into references the app can reopen tomorrow.
///
/// The bookmark is created here, at import, while permission exists. There is no
/// second chance: the permission that arrives with a drop or a picker dies with
/// the process.
public enum Importer {

    public struct Result: Sendable {
        public var references: [PhotoReference] = []
        public var failures: [(name: String, error: any Error)] = []
        public var scanned = 0
    }

    private static let log = Logger(subsystem: AppPaths.bundleIdentifier, category: "import")

    /// Formats worth importing. Deliberately broad — `public.image` catches the
    /// rest, and anything ImageIO cannot decode fails per-file rather than
    /// blocking the import.
    public static func isImage(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        return type.conforms(to: .image)
    }

    /// Folders expand to the images inside them, recursively. Dropping a shoot
    /// folder is the common case and should not require selecting 400 files.
    ///
    /// Does not open security-scoped access itself — the caller holds it open
    /// across the whole import. See ``makeReferences(for:progress:)``.
    public static func expand(_ urls: [URL]) -> [URL] {
        var found: [URL] = []
        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.contentTypeKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                while let child = enumerator?.nextObject() as? URL {
                    if isImage(child) { found.append(child) }
                }
            } else if isImage(url) {
                found.append(url)
            }
        }
        return found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Hash, measure and bookmark one photograph.
    ///
    /// `url` must be one the person just chose — from the picker, a drop, or
    /// Open With. Those are the only URLs a sandboxed app may bookmark.
    ///
    /// Assumes access is already open. Opening and closing it here as well was
    /// the bug behind "could not be read" on the picker route: see
    /// ``makeReferences(for:progress:)``.
    public static func makeReference(for url: URL) throws -> PhotoReference {
        let dimensions = try ThumbnailDecoder.probe(url: url)
        let hash = try ContentHasher.hash(contentsOf: url)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        let bookmark: Data
        do {
            bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw PhotoAccessError.unresolvable(name: url.lastPathComponent, underlying: error)
        }

        return PhotoReference(
            id: hash,
            displayName: url.lastPathComponent,
            fileSize: size,
            pixelWidth: dimensions.width,
            pixelHeight: dimensions.height,
            bookmark: bookmark
        )
    }

    /// Import in bulk, off the main thread, one failure at a time.
    ///
    /// Access is opened once per chosen URL and held for the whole import —
    /// expansion, hashing and bookmarking — then released at the end.
    ///
    /// This is not tidiness. A file chosen through the open panel is vended by
    /// Powerbox, and relinquishing that grant and asking for it again does not
    /// reliably get it back: reads kept working, and then
    /// `bookmarkData(.withSecurityScope)` failed with Cocoa error 256, so the
    /// import got far enough to look fine and then could not save the one token
    /// that lets the photograph be reopened tomorrow. A dropped URL and one from
    /// Open With both survive that round trip, which is why only the panel route
    /// appeared broken.
    public static func makeReferences(
        for urls: [URL],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> Result {
        var held: [URL] = []
        for url in urls where url.startAccessingSecurityScopedResource() {
            held.append(url)
        }
        defer { for url in held { url.stopAccessingSecurityScopedResource() } }
        log.info("import: \(held.count, privacy: .public) of \(urls.count, privacy: .public) chosen URLs opened security-scoped access")

        let files = expand(urls)
        var result = Result()
        result.scanned = files.count
        guard !files.isEmpty else { return result }

        let total = files.count
        let outcomes = await withTaskGroup(of: (Int, Swift.Result<PhotoReference, any Error>, String).self) { group in
            // Hashing is I/O bound and the disk is the limit, not the CPU. A
            // small window keeps a 400-file drop from queueing 400 reads.
            let window = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount))
            var next = 0
            var completed = 0
            var collected: [(Int, Swift.Result<PhotoReference, any Error>, String)] = []

            func submit(_ offset: Int) {
                let url = files[offset]
                group.addTask {
                    do {
                        return (offset, .success(try makeReference(for: url)), url.lastPathComponent)
                    } catch {
                        return (offset, .failure(error), url.lastPathComponent)
                    }
                }
            }

            while next < min(window, total) {
                submit(next)
                next += 1
            }
            while let outcome = await group.next() {
                collected.append(outcome)
                completed += 1
                progress?(completed, total)
                if next < total {
                    submit(next)
                    next += 1
                }
            }
            return collected.sorted { $0.0 < $1.0 }
        }

        for (_, outcome, name) in outcomes {
            switch outcome {
            case .success(let reference):
                result.references.append(reference)
            case .failure(let error):
                let underlying = (error as? PhotoAccessError).flatMap { access -> String? in
                    guard case .unresolvable(_, let cause) = access, let cause else { return nil }
                    let nsError = cause as NSError
                    return " [\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)]"
                } ?? ""
                log.error("import failed for \(name, privacy: .public): \(error.localizedDescription, privacy: .public)\(underlying, privacy: .public)")
                result.failures.append((name: name, error: error))
            }
        }
        return result
    }
}
