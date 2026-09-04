import Foundation
import CryptoKit

/// Identity of a photograph: the SHA-256 of its bytes.
///
/// A photograph is the same photograph after it is renamed or moved, and two
/// copies of one file in two collections are one photograph in All Photos. Path
/// identity gives neither. This also keys the thumbnail cache, so a cache entry
/// can never be stale with respect to its source — different bytes, different key.
public struct ContentHash: Hashable, Sendable, Codable, CustomStringConvertible {

    /// Lowercase hexadecimal, 64 characters.
    public let hex: String

    public init(hex: String) {
        self.hex = hex
    }

    fileprivate init(digest: SHA256Digest) {
        self.hex = digest.map { String(format: "%02x", $0) }.joined()
    }

    public var description: String { hex }

    /// A short form for logs and filenames-in-conversation. Never for identity.
    public var abbreviated: String { String(hex.prefix(12)) }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.hex = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

public enum ContentHasher {

    /// Read in 4 MB chunks so a 100 MB PNG never becomes a 100 MB allocation.
    static let chunkSize = 4 * 1024 * 1024

    /// Hash a file without loading it whole.
    ///
    /// The caller is responsible for security-scoped access; this takes a plain
    /// URL because it runs at import, inside the scope opened by the picker.
    public static func hash(contentsOf url: URL) throws -> ContentHash {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return ContentHash(digest: hasher.finalize())
    }

    /// The same function over bytes already in memory. Exists so the hash is
    /// testable without touching the filesystem.
    public static func hash(_ data: Data) -> ContentHash {
        ContentHash(digest: SHA256.hash(data: data))
    }
}
