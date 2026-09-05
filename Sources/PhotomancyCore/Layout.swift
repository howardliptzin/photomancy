import Foundation
import CoreGraphics

/// Where every cell sits. The only source of truth for geometry in the app.
///
/// Pure and synchronous: it draws nothing, reads nothing, and depends on no
/// state. The screen positions views with the rectangles it returns; from M5 the
/// print path takes *the same rectangles* and applies one uniform
/// scale-and-translate onto the page. Geometry is shared, drawing is not.
///
/// - Parameters:
///   - cols: Cells across. Zero or fewer yields an empty result.
///   - rows: Cells down. Zero or fewer yields an empty result.
///   - gap: Pixels between neighbouring cells **and** around the whole block.
///     One number everywhere — see the note on the block below.
///   - cellAspect: Width ÷ height of a cell. `nil` takes the canvas's own
///     proportions, so the block fills it exactly. A value that is not a
///     positive finite number is treated as `nil` rather than as an error: a
///     sheet that lays out oddly is recoverable, a sheet that fails to appear
///     is not.
///   - canvas: The window. Not the page — printing scales this result onto
///     paper rather than laying out for it.
/// - Returns: One rectangle per cell in row-major order, in the canvas's
///   coordinate space, unrounded.
///
/// Rectangles are deliberately not snapped to whole pixels. Snapping is a screen
/// concern applied when views are placed; baking it in here would carry screen
/// artefacts onto paper.
public func layout(
    cols: Int,
    rows: Int,
    gap: Double,
    cellAspect: Double?,
    canvas: CGSize
) -> [CGRect] {

    guard cols > 0, rows > 0 else { return [] }
    guard canvas.width.isFinite, canvas.height.isFinite else { return [] }

    // A window mid-animation reports sizes no arithmetic should be trusted with.
    let gap = (gap.isFinite && gap > 0) ? gap : 0
    let width = Double(canvas.width)
    let height = Double(canvas.height)

    // The outer margin equals the gap, so the margins collapse into the run:
    // `cols` cells and `cols + 1` gaps span the width, `rows` and `rows + 1` the
    // height. Two separate numbers would mean carrying a margin term through
    // every branch below, and would make "padding, exact to the pixel" mean two
    // different things.
    let widthLimit = (width - Double(cols + 1) * gap) / Double(cols)
    let heightLimit = (height - Double(rows + 1) * gap) / Double(rows)
    guard widthLimit > 0, heightLimit > 0 else { return [] }

    let cellWidth: Double
    let cellHeight: Double
    if let cellAspect, cellAspect.isFinite, cellAspect > 0 {
        // Whichever axis binds first decides the size. The cell keeps its shape;
        // the slack becomes dead space at two edges of the canvas.
        cellWidth = min(widthLimit, heightLimit * cellAspect)
        cellHeight = cellWidth / cellAspect
    } else {
        cellWidth = widthLimit
        cellHeight = heightLimit
    }

    // The block carries its own outer margin, so on the binding axis it spans
    // the canvas exactly and the centring below contributes nothing there.
    let blockWidth = Double(cols) * cellWidth + Double(cols + 1) * gap
    let blockHeight = Double(rows) * cellHeight + Double(rows + 1) * gap
    let originX = (width - blockWidth) / 2
    let originY = (height - blockHeight) / 2

    var cells: [CGRect] = []
    cells.reserveCapacity(cols * rows)
    for row in 0..<rows {
        for col in 0..<cols {
            cells.append(CGRect(
                x: originX + gap + Double(col) * (cellWidth + gap),
                y: originY + gap + Double(row) * (cellHeight + gap),
                width: cellWidth,
                height: cellHeight
            ))
        }
    }
    return cells
}
