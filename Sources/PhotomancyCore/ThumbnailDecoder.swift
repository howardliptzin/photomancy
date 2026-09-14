import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// A decoded image plus what it cost. Reference type so ``NSCache`` can hold it
/// and charge it by size.
///
/// `CGImage` is immutable and safe to read from any thread, which the compiler
/// has no way to know.
public final class Thumbnail: @unchecked Sendable {

    /// Where the pixels came from. The print path must never accept
    /// `.embeddedPreview` — a camera's preview is not the photograph.
    public enum Provenance: String, Sendable {
        case fullDecode
        case embeddedPreview
    }

    public let image: CGImage
    /// The bucket this was decoded for, not the exact dimensions.
    public let requestedMaxPixel: Int
    public let provenance: Provenance

    public init(image: CGImage, requestedMaxPixel: Int, provenance: Provenance = .fullDecode) {
        self.image = image
        self.requestedMaxPixel = requestedMaxPixel
        self.provenance = provenance
    }

    public var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    public var aspectRatio: Double {
        guard image.height > 0 else { return 1 }
        return Double(image.width) / Double(image.height)
    }

    /// Roughly what this occupies decoded, for the memory cache's cost function.
    public var byteCount: Int {
        image.height * image.bytesPerRow
    }
}

public enum ThumbnailDecoder {

    /// Where the pixels come from.
    public enum Strategy: String, Sendable, CaseIterable {
        /// Always resample the full image. Predictable quality at every size,
        /// and the number the brief's 80 ms figure has to be measured against.
        case fullDecode
        /// Use a camera's embedded preview, but only when it is genuinely big
        /// enough for the requested size, falling back to a full resample when
        /// it is not. Much faster on JPEG and HEIC; the quality and colour
        /// handling are then the camera's, not ours.
        ///
        /// The adequacy check is the whole point. Asking ImageIO for an
        /// embedded thumbnail returns whatever is embedded — often 160×120 —
        /// at whatever size it happens to be, regardless of
        /// `kCGImageSourceThumbnailMaxPixelSize`. Without the check this is
        /// not a faster path, it is a worse picture.
        case embeddedIfAdequate
    }

    /// Orientation-corrected pixel dimensions, without decoding any pixels.
    public static func probe(url: URL) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            throw PhotoAccessError.notAnImage(name: url.lastPathComponent)
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1

        // 5–8 are the transposed orientations: the stored pixels are rotated a
        // quarter turn from how the photograph is meant to be seen. Reporting the
        // stored dimensions here would give every portrait iPhone frame a
        // landscape aspect ratio.
        return (5...8).contains(orientation) ? (height, width) : (width, height)
    }

    /// Decode at display size. Never decodes the full image into memory.
    public static func decode(
        url: URL,
        maxPixelSize: Int,
        strategy: Strategy = .fullDecode
    ) throws -> Thumbnail {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw PhotoAccessError.notAnImage(name: url.lastPathComponent)
        }
        return try decode(source: source, maxPixelSize: maxPixelSize, strategy: strategy, name: url.lastPathComponent)
    }

    public static func decode(
        data: Data,
        maxPixelSize: Int,
        strategy: Strategy = .fullDecode,
        name: String = "image"
    ) throws -> Thumbnail {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw PhotoAccessError.notAnImage(name: name)
        }
        return try decode(source: source, maxPixelSize: maxPixelSize, strategy: strategy, name: name)
    }

    private static func decode(
        source: CGImageSource,
        maxPixelSize: Int,
        strategy: Strategy,
        name: String
    ) throws -> Thumbnail {
        if strategy == .embeddedIfAdequate,
           let embedded = CGImageSourceCreateThumbnailAtIndex(source, 0, options(fullDecode: false, maxPixelSize: maxPixelSize)),
           isAdequate(embedded, for: maxPixelSize, source: source) {
            return Thumbnail(image: embedded, requestedMaxPixel: maxPixelSize, provenance: .embeddedPreview)
        }

        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options(fullDecode: true, maxPixelSize: maxPixelSize)
        ) else {
            throw PhotoAccessError.decodeFailed(name: name)
        }
        return Thumbnail(image: image, requestedMaxPixel: maxPixelSize)
    }

    private static func options(fullDecode: Bool, maxPixelSize: Int) -> CFDictionary {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: fullDecode,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: fullDecode,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            // Apply the EXIF rotation now. Otherwise every consumer — the grid,
            // the lightbox, the print path — has to remember to do it.
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode on this thread, in this call. Without it the work is
            // deferred to first draw, which puts it back on the main thread and
            // makes any measurement taken here a fiction.
            kCGImageSourceShouldCacheImmediately: true,
        ] as [CFString: Any] as CFDictionary
    }

    /// Big enough means: as long on its longest edge as what was asked for — or
    /// as long as the original, when the original is smaller than the request.
    private static func isAdequate(_ image: CGImage, for maxPixelSize: Int, source: CGImageSource) -> Bool {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let target = max(width, height) > 0 ? min(maxPixelSize, max(width, height)) : maxPixelSize
        return max(image.width, image.height) >= target
    }
}

/// Requested sizes are rounded up onto a ladder so that dragging a window does
/// not re-decode the library at every intermediate width. "Re-request only when
/// the cell size changes materially" — this is what materially means.
public enum ThumbnailSize {

    /// Up to 5120 because the lightbox decodes at window size, and a photograph
    /// filling a 5K window is that long on its long edge. Stopping at 2048 left
    /// the one view meant for looking closely quietly soft on a large display.
    public static let ladder = [128, 192, 256, 384, 512, 768, 1024, 1536, 2048, 3072, 4096, 5120]

    public static func bucket(forPixels pixels: Int) -> Int {
        guard pixels > 0 else { return ladder[0] }
        return ladder.first { $0 >= pixels } ?? ladder[ladder.count - 1]
    }

    /// Points as laid out, times the display's backing scale.
    public static func bucket(forPoints points: Double, scale: Double) -> Int {
        bucket(forPixels: Int((points * max(scale, 1)).rounded(.up)))
    }

    /// The size to decode for one cell under Fit.
    ///
    /// Fit insets the photograph inside the cell, so its longest rendered edge
    /// is the *cell's* longest edge — not the cell's height, and not the width.
    /// Asking from either one alone under-decodes every photograph whose
    /// orientation differs from the cell's, and the only symptom is that some
    /// of the grid is quietly soft.
    public static func bucket(forCell size: CGSize, scale: Double) -> Int {
        bucket(forPoints: max(size.width, size.height), scale: scale)
    }
}
