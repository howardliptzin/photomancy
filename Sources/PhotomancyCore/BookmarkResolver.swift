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
            let nsError = error as NSError
            log.error("bookmark resolve failed for \(reference.displayName, privacy: .public): domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) — \(nsError.localizedDescription, privacy: .public)")
            throw BookmarkResolver.resolutionFailure(error, name: reference.displayName)
        }

        if isStale {
            refresh(url, for: reference, handler: handler)
        }

        lock.lock()
        resolved[reference.id] = url
        lock.unlock()
        return url
    }

    /// Which failure a bookmark that would not resolve actually is.
    ///
    /// A photograph that has been deleted or replaced fails here, before
    /// resolution completes — the bookmark is intact, its target is not.
    /// Reporting that as lost permission would send the person looking for a
    /// privacy setting instead of for the file.
    ///
    /// **`NSFileReadCorruptFileError` is in the list, and that is measured
    /// rather than guessed.** In the sandbox a bookmark whose target has gone
    /// resolves to Cocoa error 259 — "the file couldn't be opened because it
    /// isn't in the correct format" — and not to either no-such-file code.
    /// Measured 2026-09-22 in the running app, on a photograph copied elsewhere
    /// and deleted; the unsandboxed tests return a no-such-file code for the
    /// same situation, so the test suite alone could never have found this. The
    /// misclassification mattered: it left Relink… disabled in exactly the case
    /// it exists for. 259 is also the generic malformed-data code, so a bookmark
    /// that really is corrupt lands here too — which is right, because relinking
    /// is the repair for that as well.
    static func resolutionFailure(_ error: any Error, name: String) -> PhotoAccessError {
        let nsError = error as NSError
        let gone = nsError.domain == NSCocoaErrorDomain && [
            NSFileNoSuchFileError,
            NSFileReadNoSuchFileError,
            NSFileReadCorruptFileError,
        ].contains(nsError.code)
        return gone
            ? .missing(name: name)
            : .unresolvable(name: name, underlying: error)
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
