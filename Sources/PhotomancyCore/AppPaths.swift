import Foundation

/// Where the app keeps its own files.
///
/// Inside the sandbox these all resolve under
/// `~/Library/Containers/com.luna-park.Photomancy/Data/…`. Nothing here needs a
/// security-scoped bookmark — the container is always readable and writable.
public enum AppPaths {

    public static let bundleIdentifier = "com.luna-park.Photomancy"

    /// The directory the library and the thumbnail cache live in.
    public static func applicationSupport() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Photomancy", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func libraryFile() throws -> URL {
        try applicationSupport().appendingPathComponent("library.json", isDirectory: false)
    }

    /// Tier two of the thumbnail cache.
    ///
    /// Deliberately inside Application Support rather than Caches: the system may
    /// evict Caches at any moment, and a cold grid is the one thing the loop
    /// cannot afford. It is cheap to rebuild but expensive to rebuild *often*.
    public static func thumbnailDirectory() throws -> URL {
        let directory = try applicationSupport().appendingPathComponent("Thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
