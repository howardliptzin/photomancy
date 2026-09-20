import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import os

/// Photographs at the size they print, decoded from the originals.
///
/// Deliberately not the thumbnail cache, in either direction. It does not read
/// from it — a cell's thumbnail is decoded for a screen and is nowhere near
/// enough pixels for paper — and it does not write to it, because a print job's
/// images are far larger than anything the grid wants and would evict the whole
/// warm cache to hold pictures nobody is going to look at again. They live for
/// one job and are then dropped.
///
/// Called from the print operation's **output** pass only, never the preview.
/// The panel draws its preview on the main thread in this process; decoding
/// originals there would freeze the panel while someone is still choosing paper.
/// Step 0 found the discriminator: `preferredRenderingQuality` is `responsive`
/// for the preview and `best` for the output.
///
/// Synchronous on purpose. The output pass is already off the main thread, on a
/// thread AppKit made for it, and it draws when this returns.
public enum PrintImages {

    /// Pixels per inch on paper.
    ///
    /// 360, not 300: it is the native pitch of the photo printers this is aimed
    /// at, and at contact-sheet sizes the decode is cheap either way — a 45 mm
    /// cell wants 640 px. "Full resolution" on paper means this, not the whole
    /// original, which for a 60 MP frame would be pointless work for pixels no
    /// printer lays down.
    public static let pixelsPerInch: Double = 360

    /// What the PDF carries each photograph as. Step 0 measured the difference
    /// on 20 photographs at 1,300 px: 36.0 MB as decoded samples against 7.4 MB
    /// as quality-0.92 JPEG, and three times faster to write.
    public static let jpegQuality: Double = 0.92

    /// One photograph and the cell it prints in.
    public struct Placement: Sendable {
        public let cell: Int
        public let reference: PhotoReference

        public init(cell: Int, reference: PhotoReference) {
            self.cell = cell
            self.reference = reference
        }
    }

    /// Photographs the job needs and cannot read.
    ///
    /// A missing photograph must never print as background: on paper that is
    /// indistinguishable from an empty cell, so the sheet would come out short
    /// one frame and look deliberate. The job stops instead and names them, so
    /// the whole list can be relinked in one go rather than one printing at a
    /// time.
    public struct PhotographsMissing: Error, LocalizedError, Sendable {
        public let names: [String]

        public init(names: [String]) {
            self.names = names
        }

        public var errorDescription: String? {
            guard let first = names.first else { return "A photograph can’t be found." }
            guard names.count > 1 else { return "“\(first)” can’t be found." }
            let shown = names.prefix(3).joined(separator: ", ")
            let rest = names.count - min(names.count, 3)
            return rest > 0
                ? "\(names.count) photographs can’t be found: \(shown), and \(rest) more."
                : "\(names.count) photographs can’t be found: \(shown)."
        }

        public var recoverySuggestion: String? {
            "Select \(names.count > 1 ? "them" : "it") on the sheet and choose Relink…"
        }
    }

    private static let log = Logger(subsystem: AppPaths.bundleIdentifier, category: "print")

    /// The long edge, in pixels, to decode a photograph that will be drawn at
    /// `size` points on paper.
    ///
    /// 72 points to the inch, so at 360 ppi this is simply five pixels per
    /// point. Capped at the original, because ImageIO does not enlarge: asking
    /// a 1,600-pixel file for 3,000 returns 1,600 and only wastes the request.
    /// From the photograph's *drawn* size and not its cell's — under Fit a
    /// portrait frame in a square cell is drawn at the cell's height, and
    /// sizing from the cell would decode more than is ever laid down.
    public static func pixels(
        forPhotographDrawnAt size: CGSize,
        originalLongEdge: Int,
        pixelsPerInch: Double = PrintImages.pixelsPerInch
    ) -> Int {
        let points = max(size.width, size.height)
        guard points.isFinite, points > 0, pixelsPerInch.isFinite, pixelsPerInch > 0 else { return 1 }
        let wanted = max(1, Int((points / 72 * pixelsPerInch).rounded(.up)))
        return originalLongEdge > 0 ? min(wanted, originalLongEdge) : wanted
    }

    /// Decode every placed photograph at the size it prints on this page.
    ///
    /// - Throws: ``PhotographsMissing`` when any original cannot be reached —
    ///   checked for all of them before a single one is decoded, so a job with
    ///   a missing file fails in milliseconds and names the whole list rather
    ///   than spending a second decoding the others first.
    public static func frames(
        for placements: [Placement],
        geometry: SheetGeometry,
        printable: CGRect,
        resolver: BookmarkResolver,
        pixelsPerInch: Double = PrintImages.pixelsPerInch,
        jpegQuality: Double = PrintImages.jpegQuality
    ) throws -> [SheetRenderer.Frame] {

        let placements = placements.filter { geometry.cells.indices.contains($0.cell) }
        guard !placements.isEmpty else { return [] }

        // Everything the job needs, reached before any of it is decoded.
        //
        // Only a file that is gone is collected. Lost permission and an
        // unresolvable bookmark propagate as themselves: they already carry
        // accurate messages, and calling them "can't be found" would send
        // someone looking in the Finder for a file that is exactly where they
        // left it — the same mistake `BookmarkResolver` takes care not to make
        // in the other direction.
        var missing: [String] = []
        for placement in placements.sorted(by: { $0.cell < $1.cell }) {
            do {
                try resolver.withAccess(placement.reference) { _ in }
            } catch PhotoAccessError.missing {
                missing.append(placement.reference.displayName)
            }
        }
        guard missing.isEmpty else { throw PhotographsMissing(names: missing) }

        let transform = pageTransform(from: geometry.block, onto: printable)
        var frames: [SheetRenderer.Frame] = []
        frames.reserveCapacity(placements.count)

        for placement in placements {
            let cell = geometry.cells[placement.cell].applying(transform)
            let drawn = fitted(aspectRatio: placement.reference.aspectRatio, in: cell)
            let longEdge = pixels(
                forPhotographDrawnAt: drawn.size,
                originalLongEdge: max(placement.reference.pixelWidth, placement.reference.pixelHeight),
                pixelsPerInch: pixelsPerInch
            )

            let decoded = try resolver.withAccess(placement.reference) { url in
                try ThumbnailDecoder.decode(url: url, maxPixelSize: longEdge, strategy: .fullDecode)
            }
            // Enforced rather than assumed. A camera's embedded preview is not
            // the photograph, and it is small enough that the difference would
            // only show up on paper, after the ink.
            guard decoded.provenance == .fullDecode else {
                throw PhotoAccessError.decodeFailed(name: placement.reference.displayName)
            }

            let image = compressed(decoded.image, quality: jpegQuality) ?? decoded.image
            frames.append(SheetRenderer.Frame(cell: placement.cell, image: image))
        }

        log.info("print: decoded \(frames.count, privacy: .public) photographs for paper")
        return frames
    }

    /// The same picture, carried as JPEG.
    ///
    /// A `CGImage` backed by JPEG data is embedded in a PDF as that JPEG, so
    /// the file holds compressed photographs instead of raw samples. Drawn to a
    /// printer it is identical. `nil` if it cannot be encoded, and the caller
    /// then prints the decoded image — a bigger spool file is a far better
    /// outcome than a page that does not print.
    ///
    /// Lossy, at a quality where it is not visible at 360 ppi, and applied once
    /// to an image that is already at its final size. The original on disk is
    /// never touched.
    public static func compressed(_ image: CGImage, quality: Double = PrintImages.jpegQuality) -> CGImage? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let provider = CGDataProvider(data: data as CFData)
        else { return nil }

        // This initialiser, rather than an image source: it is the one that
        // keeps the JPEG itself as the image's data, which is what lets Quartz
        // pass it through into a PDF instead of re-encoding the samples.
        return CGImage(
            jpegDataProviderSource: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
