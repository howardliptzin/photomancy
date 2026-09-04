import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Tier two: decoded thumbnails written back to Application Support so a cold
/// launch is not a cold decode.
///
/// Keyed by content hash and pixel bucket, so an entry can never be stale with
/// respect to its source — different bytes produce a different key.
public struct DiskThumbnailCache: Sendable {

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Pure, and therefore testable. `alpha` decides the container, because
    /// JPEG would silently flatten a PNG with transparency onto black.
    public static func filename(for id: ContentHash, pixels: Int, alpha: Bool) -> String {
        "\(id.hex)@\(pixels).\(alpha ? "png" : "jpg")"
    }

    func url(for id: ContentHash, pixels: Int, alpha: Bool) -> URL {
        directory.appendingPathComponent(Self.filename(for: id, pixels: pixels, alpha: alpha), isDirectory: false)
    }

    /// Both containers are probed because the alpha-ness of a photograph is not
    /// known until it has been decoded once.
    public func load(id: ContentHash, pixels: Int) -> Thumbnail? {
        for alpha in [false, true] {
            let candidate = url(for: id, pixels: pixels, alpha: alpha)
            guard let source = CGImageSourceCreateWithURL(candidate as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [
                      kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary)
            else { continue }
            return Thumbnail(image: image, requestedMaxPixel: pixels)
        }
        return nil
    }

    public func store(_ thumbnail: Thumbnail, id: ContentHash, pixels: Int) {
        let alpha = Self.hasAlpha(thumbnail.image)
        let destinationURL = url(for: id, pixels: pixels, alpha: alpha)
        let type = (alpha ? UTType.png : UTType.jpeg).identifier as CFString

        // Write beside the target and move into place, so a cache entry is never
        // half a file if the app is quit mid-write.
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp", isDirectory: false)
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type, 1, nil) else { return }

        let properties: [CFString: Any] = alpha ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.9]
        CGImageDestinationAddImage(destination, thumbnail.image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temporary)
            return
        }
        _ = try? FileManager.default.replaceItemAt(destinationURL, withItemAt: temporary)
        try? FileManager.default.removeItem(at: temporary)
    }

    public func removeAll() throws {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for item in contents { try? FileManager.default.removeItem(at: item) }
    }

    public func entryCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)))?
            .filter { !$0.hasPrefix(".") }.count ?? 0
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }
}
