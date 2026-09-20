import Foundation
import CoreGraphics

/// Draws a sheet into any `CGContext`.
///
/// Geometry is shared, drawing is not: the screen positions SwiftUI views with
/// the rectangles `sheetGeometry()` returns, and this draws into the *same*
/// rectangles under `pageTransform`. Neither knows about the other, and there is
/// no second layout for either to disagree with.
///
/// **A plain struct over immutable data, and deliberately not an `NSView`.**
/// Printing renders the output pass on a thread of its own — measured in step 0,
/// with a crash. Under Swift 6 an `NSView` subclass's overrides are implicitly
/// `@MainActor`, so a printed view that looks perfectly ordinary traps the
/// moment AppKit draws it off the main thread. Everything that decides what the
/// page looks like lives here, where it is `Sendable`, testable without a window
/// server, and indifferent to which thread it runs on. The `NSView` that hands
/// this to `NSPrintOperation` holds nothing but the data and marks every
/// override `nonisolated`.
///
/// What it draws: the background over the block, and each photograph fitted in
/// its cell. Nothing else. No pin marks, no selection rings, no outline for an
/// empty cell, no placeholder — those belong to the screen. A printed sheet
/// carries photographs and background, and a grid that is not full looks like a
/// grid that is not full.
public struct SheetRenderer: @unchecked Sendable {

    /// One photograph, already decoded, and the cell it belongs in.
    ///
    /// `CGImage` is immutable and safe to read from any thread, which the
    /// compiler has no way to know — the same reason `Thumbnail` is
    /// `@unchecked Sendable`.
    public struct Frame: @unchecked Sendable {
        public let cell: Int
        public let image: CGImage

        public init(cell: Int, image: CGImage) {
            self.cell = cell
            self.image = image
        }
    }

    public let geometry: SheetGeometry
    public let background: SheetColor

    /// Only the cells that have a photograph. A cell with no frame draws
    /// background and nothing else, which is exactly what an empty cell is.
    ///
    /// Where the pixels came from is the caller's business, and has to be: the
    /// print panel's preview is a screen and draws thumbnails, while the output
    /// pass decodes originals at the size they print. A photograph that cannot
    /// be read never reaches here — it stops the job and is named, because on
    /// paper a missing photograph would look exactly like an empty cell.
    public let frames: [Frame]

    public init(geometry: SheetGeometry, background: SheetColor, frames: [Frame]) {
        self.geometry = geometry
        self.background = background
        self.frames = frames
    }

    /// What this renderer will do to every rectangle, for anyone who needs to
    /// know before or after the fact — the print panel's millimetres, and the
    /// script that checks a printed PDF against the window.
    public func transform(onto printable: CGRect) -> CGAffineTransform {
        pageTransform(from: geometry.block, onto: printable)
    }

    /// Draw the sheet, scaled to fit `printable`.
    ///
    /// - Parameters:
    ///   - context: Any context — a PDF page, a printer's, a bitmap under test.
    ///   - printable: The page's imageable rectangle, in the context's own
    ///     coordinates: Quartz's, with y upward.
    public func draw(in context: CGContext, onto printable: CGRect) {
        guard !geometry.cells.isEmpty else { return }
        let transform = self.transform(onto: printable)

        // The transform is applied to the *rectangles*, never concatenated into
        // the context. It has to be. `pageTransform` carries the flip from the
        // screen's top-left origin to Quartz's bottom-left as a negative y
        // scale, and a context drawing under that matrix would render every
        // photograph upside down while every rectangle still landed in exactly
        // the right place. Mapping rectangles into page space and drawing them
        // in an untouched context is what keeps the flip a change of
        // coordinates rather than a change to the pictures.

        context.saveGState()
        defer { context.restoreGState() }

        // Photographs are drawn at the size they print but rarely at exactly
        // the cell's pixel count, so the last resample is Quartz's and must be
        // a good one.
        context.interpolationQuality = .high

        // The block, and not a millimetre more. The window's dead space at the
        // two edges that do not bind is not part of the composition — scaling
        // the whole window onto A4 made every photograph 59% smaller for
        // nothing (settled 2026-09-19). Outside the block is paper.
        context.setFillColor(background.cgColor)
        context.fill(geometry.block.applying(transform))

        for frame in frames where geometry.cells.indices.contains(frame.cell) {
            let cell = geometry.cells[frame.cell].applying(transform)
            guard frame.image.width > 0, frame.image.height > 0 else { continue }
            let aspect = Double(frame.image.width) / Double(frame.image.height)
            // Fit, as on screen: the whole frame, centred, background around
            // it. Cropping is the photographer's decision and this app does
            // not make it.
            context.draw(frame.image, in: fitted(aspectRatio: aspect, in: cell))
        }
    }
}
