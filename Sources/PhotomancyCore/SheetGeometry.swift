import Foundation
import CoreGraphics

/// The sheet's geometry, once, for both the screen and the page.
///
/// `layout()` answers "where are the cells". This answers the whole question the
/// two renderers actually ask: the cells, the gap they were laid out at, and the
/// block they occupy. The gap matters because the screen does not always lay out
/// at the stored one — a window made smaller than the stored gap allows lays out
/// at the largest gap that still shows cells rather than going blank — and if the
/// print path called `layout()` with the stored gap instead, the two geometries
/// would differ in exactly that case. One function, called by both, and the case
/// cannot arise.
public struct SheetGeometry: Sendable, Equatable {

    /// One rectangle per cell, row-major, in the canvas's coordinate space.
    public let cells: [CGRect]

    /// The gap the cells were actually laid out at, which is the stored gap
    /// unless the window was too small for it.
    public let gap: Double

    /// The cells and their outer gap: what is composed, and the only thing that
    /// is printed. The window's dead space at the two non-binding edges is not
    /// part of the composition — settled 2026-09-19, after scaling the whole
    /// window onto A4 made every photograph 59% smaller for nothing.
    ///
    /// Derived from the cells rather than recomputed, so it is the bounding box
    /// of what is drawn by construction and cannot drift from it.
    public let block: CGRect

    /// Nothing to lay out: a window with no size yet, or a grid with no cells.
    public static let empty = SheetGeometry(cells: [], gap: 0, block: .zero)

    init(cells: [CGRect], gap: Double, block: CGRect) {
        self.cells = cells
        self.gap = gap
        self.block = block
    }
}

/// The geometry of one sheet in one canvas. Pure, and the single source of
/// truth: `SheetView` positions views with it and the print path scales it.
///
/// - Parameters:
///   - settings: The collection's sheet settings — columns, rows and the
///     stored gap.
///   - cellAspect: Width ÷ height of a cell, already resolved from the
///     collection's `CellShape`. `nil` takes the canvas's own proportions.
///   - canvas: The window. Never the page.
public func sheetGeometry(
    settings: SheetSettings,
    cellAspect: Double?,
    canvas: CGSize
) -> SheetGeometry {

    // A window mid-animation, or a stored gap from a file that was edited by
    // hand, must lay out oddly rather than not at all.
    let requested = (settings.gap.isFinite && settings.gap > 0) ? settings.gap : 0
    let gap = min(requested, maximumGap(cols: settings.columns, rows: settings.rows, canvas: canvas))

    let cells = layout(
        cols: settings.columns,
        rows: settings.rows,
        gap: gap,
        cellAspect: cellAspect,
        canvas: canvas
    )
    guard let first = cells.first else { return .empty }

    var block = first
    for cell in cells.dropFirst() { block = block.union(cell) }
    return SheetGeometry(cells: cells, gap: gap, block: block.insetBy(dx: -gap, dy: -gap))
}

/// One uniform scale-and-translate that puts the sheet's block on the page.
///
/// Print recomputes no geometry. It takes the rectangles `sheetGeometry()`
/// already produced for the window and maps them with this, which is why a
/// printed sheet cannot be laid out differently from the one on screen: there is
/// only one layout, and this is a change of coordinates over it.
///
/// **The flip lives here.** SwiftUI puts the origin at the top left and Quartz at
/// the bottom left. Applied in the view instead, the sheet prints upside down and
/// every geometry test still passes, because the geometry would be right and only
/// the drawing wrong. Inside the transform it is tested: cell zero lands at the
/// top left of the page.
///
/// - Parameters:
///   - block: The sheet's block, in the window's top-left-origin space.
///   - printable: The page's imageable rectangle, in Quartz's bottom-left-origin
///     space — `NSPrintInfo.imageablePageBounds`.
/// - Returns: A transform mapping window points to page points: uniform in both
///   axes, centred in `printable`, y inverted. `.identity` for input nothing can
///   be done with, so a degenerate window prints something rather than trapping.
public func pageTransform(from block: CGRect, onto printable: CGRect) -> CGAffineTransform {
    guard isUsable(block), isUsable(printable) else { return .identity }

    // Whichever axis binds decides it; the slack becomes blank paper on two
    // sides. The cell's shape is held on paper exactly as it is on screen.
    let scale = min(printable.width / block.width, printable.height / block.height)

    let tx = printable.minX + (printable.width - block.width * scale) / 2 - scale * block.minX
    // The block's *top* edge maps to the top of the centred area, and y descends
    // from there — which is the flip, written as the d and ty of one matrix.
    let ty = printable.minY + (printable.height + block.height * scale) / 2 + scale * block.minY

    return CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: tx, ty: ty)
}

private func isUsable(_ rect: CGRect) -> Bool {
    rect.minX.isFinite && rect.minY.isFinite
        && rect.width.isFinite && rect.height.isFinite
        && rect.width > 0 && rect.height > 0
}

/// What the sheet will actually measure on paper.
///
/// The gap is pixels on screen and proportional on paper — printing scales the
/// whole sheet uniformly, so a 12 px gap is not a fixed physical measure. Rather
/// than pretend otherwise, the print panel states the millimetres this comes to,
/// and they change as the window and the paper do.
public struct PrintMetrics: Sendable, Hashable {

    /// Millimetres.
    public let cell: CGSize
    /// Millimetres.
    public let gap: Double
    /// Page points per window point. The same number the drawing uses.
    public let scale: Double

    /// What the print panel's accessory view says. Built here rather than in the
    /// view, so the sentence is tested like everything else.
    public var summary: String {
        "Cells \(Self.millimetres(cell.width)) × \(Self.millimetres(cell.height)) mm · gap \(Self.millimetres(gap)) mm"
    }

    private static func millimetres(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

/// The printed size of a cell and a gap, for this sheet on this page.
///
/// Read off the same transform that draws, so the figure in the panel and the
/// ink on the paper cannot disagree. `nil` when there is no sheet to measure.
public func printMetrics(for geometry: SheetGeometry, onto printable: CGRect) -> PrintMetrics? {
    guard let cell = geometry.cells.first, isUsable(geometry.block), isUsable(printable) else { return nil }
    let scale = pageTransform(from: geometry.block, onto: printable).a
    guard scale.isFinite, scale > 0 else { return nil }

    func millimetres(_ points: Double) -> Double { points * 25.4 / 72 }
    return PrintMetrics(
        cell: CGSize(
            width: millimetres(cell.width * scale),
            height: millimetres(cell.height * scale)
        ),
        gap: millimetres(geometry.gap * scale),
        scale: scale
    )
}
