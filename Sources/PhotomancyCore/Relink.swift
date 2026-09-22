import Foundation
import os

/// Pointing a photograph at where its file has gone.
///
/// Files move. That is normal rather than an error state, and the library is
/// built for it: a photograph is identified by the hash of its contents, so a
/// file that has been moved or renamed is still the same photograph and can be
/// found again. What a relink replaces is only the bookmark — the permission
/// token — and the name shown.
///
/// **Strictly by content.** The candidate must hash identically, byte for byte.
/// A re-exported edit, a re-saved JPEG, the same frame at another quality: all
/// different photographs, and none of them relink. The alternative — matching
/// on name, or dimensions, or a perceptual likeness — would silently put a
/// different picture in a sequence the photographer had already chosen, which
/// is the one failure this must not have.
public enum Relink {

    /// A photograph the library holds and cannot currently read.
    public struct Missing: Sendable, Hashable {
        public let id: ContentHash
        public let displayName: String
        public let fileSize: Int
    }

    public enum Failure: Error, LocalizedError, Sendable {
        /// The file is readable and is a different photograph.
        case differentPhotograph(chosen: String, expected: String)
        case notInLibrary
        case unreadable(name: String, underlying: (any Error)?)

        public var errorDescription: String? {
            switch self {
            case .differentPhotograph(let chosen, let expected):
                "“\(chosen)” is not the same photograph as “\(expected)”."
            case .notInLibrary:
                "That photograph is not in the library any more."
            case .unreadable(let name, _):
                "“\(name)” could not be read."
            }
        }

        public var recoverySuggestion: String? {
            switch self {
            case .differentPhotograph:
                "Relinking matches the file's contents exactly, so an edited or "
                    + "re-exported copy counts as a different photograph."
            default: nil
            }
        }
    }

    private static let log = Logger(subsystem: AppPaths.bundleIdentifier, category: "relink")

    /// A bookmark for a file the person has just chosen, which is what makes it
    /// readable again after a quit.
    ///
    /// Read-only, like every other bookmark this app creates — a relink must not
    /// quietly upgrade a photograph to a token the app is not entitled to use.
    static func bookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: bookmarkCreationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw Failure.unreadable(name: url.lastPathComponent, underlying: error)
        }
    }

    /// Does this file's byte size make it worth hashing against this photograph?
    ///
    /// Identical content means identical length, so a size mismatch rules a
    /// candidate out with a `stat` instead of a full read. On a folder of a few
    /// hundred RAW files this is the difference between hashing gigabytes and
    /// hashing the handful that could possibly match.
    static func couldMatch(size: Int, _ missing: Missing) -> Bool {
        missing.fileSize > 0 && size == missing.fileSize
    }

    /// Everything in `folder`, one level deep, that a missing photograph could be.
    ///
    /// Size first, then the hash, and only for the sizes that survive. Returns
    /// the pairing it found; relinking them is the caller's step, because it is
    /// the caller that owns the library.
    public static func search(
        folder: URL,
        for missing: [Missing]
    ) -> [(missing: Missing, url: URL)] {
        guard !missing.isEmpty else { return [] }
        let wanted = Dictionary(grouping: missing, by: \.fileSize)

        let candidates = Importer.expand([folder])
        var found: [(missing: Missing, url: URL)] = []
        var claimed = Set<ContentHash>()
        var hashed = 0

        for url in candidates {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard let sameSize = wanted[size], sameSize.contains(where: { !claimed.contains($0.id) })
            else { continue }

            hashed += 1
            guard let hash = try? ContentHasher.hash(contentsOf: url) else { continue }
            guard let match = sameSize.first(where: { $0.id == hash && !claimed.contains($0.id) })
            else { continue }

            claimed.insert(match.id)
            found.append((match, url))
        }

        log.info("relink: \(candidates.count, privacy: .public) files, \(hashed, privacy: .public) worth hashing, \(found.count, privacy: .public) found")
        return found
    }
}

extension PhotoReference {
    /// Same photograph — same id, same pixels, same size on disk — found again
    /// somewhere else.
    func relinked(to name: String, bookmark data: Data) -> PhotoReference {
        PhotoReference(
            id: id,
            displayName: name,
            fileSize: fileSize,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            addedAt: addedAt,
            bookmark: data
        )
    }
}
