import Foundation
import os

/// The only route from a ``PhotoReference`` to bytes on disk.
///
/// Every read is wrapped in `startAccessingSecurityScopedResource()` /
/// `stopAccessing…`. Nothing hands out a `URL` that outlives the closure, so no
/// later code can forget to redeem the bookmark.
///
/// Thread-safe: thumbnail decoding happens on a background queue, and security
/// scoped access is per-process rather than per-thread, so resolution is shared
/// across threads behind a lock.
public final class BookmarkResolver: @unchecked Sendable {

    private let lock = NSLock()

    /// Resolving a bookmark costs a few hundred microseconds and the result is
    /// stable for the life of the process, so it is cached. The *access* is not
    /// cached — that is still started and stopped around every read.
    private var resolved: [ContentHash: URL] = [:]

    /// Called when a bookmark had to be recreated because it went stale. The
    /// store persists the new one; if it is not written back, the same expensive
    /// refresh happens on every launch until the day it finally fails.
    private var refreshHandler: (@Sendable (ContentHash, Data) -> Void)?

    private let log = Logger(subsystem: AppPaths.bundleIdentifier, category: "bookmarks")

    public init() {}

    public func onBookmarkRefresh(_ handler: @escaping @Sendable (ContentHash, Data) -> Void) {
        lock.lock()
        refreshHandler = handler
        lock.unlock()
    }

    /// Run `body` with security-scoped access open on the photograph's file.
    ///
    /// The URL is valid only for the duration of `body`. Do not store it.
    public func withAccess<T>(
        _ reference: PhotoReference,
        _ body: (URL) throws -> T
    ) throws -> T {
        let url = try resolve(reference)

        guard url.startAccessingSecurityScopedResource() else {
            throw PhotoAccessError.accessDenied(name: reference.displayName)
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw PhotoAccessError.missing(name: reference.displayName)
        }
        return try body(url)
    }

    /// Drop a cached resolution — used after a relink, when the same photograph
    /// now lives behind a different bookmark.
    public func forget(_ id: ContentHash) {
        lock.lock()
        resolved[id] = nil
        lock.unlock()
    }

    // MARK: - Resolution

    private func resolve(_ reference: PhotoReference) throws -> URL {
        lock.lock()
        if let cached = resolved[reference.id] {
            lock.unlock()
            return cached
        }
        let handler = refreshHandler
        lock.unlock()

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: reference.bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            // A photograph that has been deleted or moved fails here, before
            // resolution completes — the bookmark is fine, the file is not.
            // Reporting that as lost permission would send the person looking
            // for a privacy setting instead of the file.
            let nsError = error as NSError
            let notFound = nsError.domain == NSCocoaErrorDomain
                && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(nsError.code)
            throw notFound
                ? PhotoAccessError.missing(name: reference.displayName)
                : PhotoAccessError.unresolvable(name: reference.displayName, underlying: error)
        }

        if isStale {
            refresh(url, for: reference, handler: handler)
        }

        lock.lock()
        resolved[reference.id] = url
        lock.unlock()
        return url
    }

    /// A stale bookmark still resolves — it just will not keep resolving. Make a
    /// new one now, while access is available, and hand it back to be saved.
    private func refresh(
        _ url: URL,
        for reference: PhotoReference,
        handler: (@Sendable (ContentHash, Data) -> Void)?
    ) {
        guard url.startAccessingSecurityScopedResource() else {
            log.error("stale bookmark for \(reference.displayName, privacy: .public): access refused, cannot refresh")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try url.bookmarkData(
                options: bookmarkCreationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            log.info("refreshed stale bookmark for \(reference.displayName, privacy: .public)")
            handler?(reference.id, data)
        } catch {
            log.error("could not recreate stale bookmark for \(reference.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
