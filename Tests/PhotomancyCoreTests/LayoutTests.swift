import XCTest
import CoreGraphics
@testable import PhotomancyCore

/// The whole reason `layout()` is pure: none of this needs a window, a
/// screenshot or an eye.
final class LayoutTests: XCTestCase {

    private let epsilon = 1e-9

    // MARK: - Count and order

    func testReturnsOneRectanglePerCellInRowMajorOrder() {
        let cells = layout(cols: 5, rows: 4, gap: 12, cellAspect: 1, canvas: CGSize(width: 1200, height: 800))
        XCTAssertEqual(cells.count, 20)

        // Row-major: the first five share a top edge, and each is right of the last.
        for index in 1..<5 {
            XCTAssertEqual(cells[index].minY, cells[0].minY, accuracy: epsilon)
            XCTAssertGreaterThan(cells[index].minX, cells[index - 1].minX)
        }
        XCTAssertGreaterThan(cells[5].minY, cells[0].minY, "the sixth cell starts a new row")
        XCTAssertEqual(cells[5].minX, cells[0].minX, accuracy: epsilon)
    }

    // MARK: - Uniformity

    func testEveryCellIsTheSameSizeAtTheRequestedAspect() {
        for aspect in [1.0, 1.5, 4.0 / 3.0, 0.5, 2.5] {
            let cells = layout(cols: 4, rows: 3, gap: 9, cellAspect: aspect, canvas: CGSize(width: 1000, height: 900))
            let first = try? XCTUnwrap(cells.first)
            for cell in cells {
                XCTAssertEqual(cell.width, first?.width ?? 0, accuracy: epsilon)
                XCTAssertEqual(cell.height, first?.height ?? 0, accuracy: epsilon)
                XCTAssertEqual(cell.width / cell.height, aspect, accuracy: 1e-9, "aspect \(aspect)")
            }
        }
    }

    /// Cells never distort to fill a window. Screen space is free.
    func testCellShapeIsHeldAcrossWildlyDifferentCanvases() {
        let canvases = [CGSize(width: 400, height: 2000), CGSize(width: 3000, height: 300), CGSize(width: 900, height: 900)]
        for canvas in canvases {
            let cells = layout(cols: 3, rows: 3, gap: 6, cellAspect: 1, canvas: canvas)
            XCTAssertEqual(cells[0].width, cells[0].height, accuracy: epsilon, "canvas \(canvas)")
        }
    }

    // MARK: - Gaps, including the outer margin

    func testGapSeparatesNeighboursAndSurroundsTheBlock() {
        let gap = 12.0
        let canvas = CGSize(width: 1200, height: 800)
        let cells = layout(cols: 5, rows: 4, gap: gap, cellAspect: 1, canvas: canvas)

        // Between neighbours, across and down.
        XCTAssertEqual(cells[1].minX - cells[0].maxX, gap, accuracy: epsilon)
        XCTAssertEqual(cells[5].minY - cells[0].maxY, gap, accuracy: epsilon)

        // And around the block: the outer margin is the same number. At this
        // canvas the height binds — 5 square cells across 1200 could be 225.6
        // wide, but 4 down 800 can only be 185 — so it is the vertical run that
        // spans exactly and the width that carries the slack.
        let blockLeft = cells[0].minX - gap
        let blockRight = cells[4].maxX + gap
        let blockTop = cells[0].minY - gap
        let blockBottom = cells[19].maxY + gap
        XCTAssertEqual(blockBottom - blockTop, Double(canvas.height), accuracy: epsilon,
                       "the binding axis is spanned exactly, outer margins included")
        XCTAssertLessThan(blockRight - blockLeft, Double(canvas.width),
                          "and the other axis has slack, which becomes dead space")
        XCTAssertEqual(cells[0].height, 185, accuracy: epsilon)
    }

    func testAHairlineGapIsHonouredExactly() {
        let cells = layout(cols: 8, rows: 8, gap: 1, cellAspect: 1, canvas: CGSize(width: 1600, height: 1200))
        XCTAssertEqual(cells.count, 64)
        XCTAssertEqual(cells[1].minX - cells[0].maxX, 1, accuracy: epsilon)
        XCTAssertEqual(cells[0].minX - 0, 1 + (1600 - (8 * cells[0].width + 9)) / 2, accuracy: epsilon)
    }

    func testAZeroGapPacksCellsEdgeToEdgeAgainstTheCanvas() {
        let canvas = CGSize(width: 900, height: 600)
        let cells = layout(cols: 3, rows: 2, gap: 0, cellAspect: nil, canvas: canvas)
        XCTAssertEqual(cells[0].minX, 0, accuracy: epsilon)
        XCTAssertEqual(cells[0].minY, 0, accuracy: epsilon)
        XCTAssertEqual(cells[2].maxX, Double(canvas.width), accuracy: epsilon)
        XCTAssertEqual(cells[5].maxY, Double(canvas.height), accuracy: epsilon)
    }

    // MARK: - Centring

    func testTheBlockIsCentredOnTheAxisThatDoesNotBind() {
        let gap = 10.0
        let canvas = CGSize(width: 1600, height: 600)   // wide: height binds
        let cells = layout(cols: 4, rows: 2, gap: gap, cellAspect: 1, canvas: canvas)

        let leftInset = cells[0].minX
        let rightInset = Double(canvas.width) - cells[3].maxX
        XCTAssertEqual(leftInset, rightInset, accuracy: epsilon)
        XCTAssertGreaterThan(leftInset, gap, "a wide canvas leaves dead space at both sides")

        let topInset = cells[0].minY
        let bottomInset = Double(canvas.height) - cells[7].maxY
        XCTAssertEqual(topInset, bottomInset, accuracy: epsilon)
        XCTAssertEqual(topInset, gap, accuracy: epsilon, "the binding axis is filled to the margin")
    }

    func testTheOtherAxisBindsWhenTheCanvasIsTall() {
        let canvas = CGSize(width: 600, height: 1600)
        let cells = layout(cols: 2, rows: 4, gap: 10, cellAspect: 1, canvas: canvas)
        XCTAssertEqual(cells[0].minX, 10, accuracy: epsilon, "width binds")
        XCTAssertGreaterThan(cells[0].minY, 10, "and height has slack")
    }

    // MARK: - Containment

    func testNoCellEverLeavesTheCanvas() {
        let canvases = [CGSize(width: 1200, height: 800), CGSize(width: 320, height: 1400), CGSize(width: 2560, height: 120)]
        for canvas in canvases {
            for aspect in [1.0, 1.5, 0.4] {
                let cells = layout(cols: 6, rows: 5, gap: 4, cellAspect: aspect, canvas: canvas)
                for cell in cells {
                    XCTAssertGreaterThanOrEqual(cell.minX, -epsilon, "\(canvas) \(aspect)")
                    XCTAssertGreaterThanOrEqual(cell.minY, -epsilon, "\(canvas) \(aspect)")
                    XCTAssertLessThanOrEqual(cell.maxX, Double(canvas.width) + epsilon, "\(canvas) \(aspect)")
                    XCTAssertLessThanOrEqual(cell.maxY, Double(canvas.height) + epsilon, "\(canvas) \(aspect)")
                }
            }
        }
    }

    /// `nil` takes the canvas's own proportions, so there is no dead space at all.
    func testANilAspectFillsBothAxesExactly() {
        let canvas = CGSize(width: 1234, height: 789)
        let gap = 7.0
        let cells = layout(cols: 5, rows: 3, gap: gap, cellAspect: nil, canvas: canvas)

        XCTAssertEqual(cells[0].minX, gap, accuracy: epsilon)
        XCTAssertEqual(cells[0].minY, gap, accuracy: epsilon)
        XCTAssertEqual(cells[4].maxX, Double(canvas.width) - gap, accuracy: epsilon)
        XCTAssertEqual(cells[14].maxY, Double(canvas.height) - gap, accuracy: epsilon)
    }

    // MARK: - Degenerate input

    /// A split view reports these while it animates. The symptom of getting it
    /// wrong is a sheet that disappears for a frame, or a crash.
    func testDegenerateInputYieldsNothingRatherThanNonsense() {
        let canvas = CGSize(width: 1000, height: 800)
        XCTAssertTrue(layout(cols: 0, rows: 4, gap: 8, cellAspect: 1, canvas: canvas).isEmpty)
        XCTAssertTrue(layout(cols: 4, rows: 0, gap: 8, cellAspect: 1, canvas: canvas).isEmpty)
        XCTAssertTrue(layout(cols: -3, rows: 4, gap: 8, cellAspect: 1, canvas: canvas).isEmpty)
        XCTAssertTrue(layout(cols: 4, rows: 4, gap: 8, cellAspect: 1, canvas: .zero).isEmpty)
        XCTAssertTrue(layout(cols: 4, rows: 4, gap: 8, cellAspect: 1, canvas: CGSize(width: -100, height: 500)).isEmpty)
        XCTAssertTrue(layout(cols: 4, rows: 4, gap: 8, cellAspect: 1,
                             canvas: CGSize(width: CGFloat.nan, height: 500)).isEmpty)
        XCTAssertTrue(layout(cols: 4, rows: 4, gap: 8, cellAspect: 1,
                             canvas: CGSize(width: CGFloat.infinity, height: 500)).isEmpty)
    }

    func testAGapTooLargeForTheCanvasYieldsNothing() {
        XCTAssertTrue(layout(cols: 5, rows: 4, gap: 500, cellAspect: 1,
                             canvas: CGSize(width: 1000, height: 800)).isEmpty)
    }

    func testNoResultEverContainsANonFiniteOrNegativeSize() {
        for cols in 1...9 {
            for rows in 1...9 {
                let cells = layout(cols: cols, rows: rows, gap: 3, cellAspect: 1.5,
                                   canvas: CGSize(width: 977, height: 613))
                for cell in cells {
                    XCTAssertTrue(cell.width.isFinite && cell.height.isFinite)
                    XCTAssertGreaterThan(cell.width, 0)
                    XCTAssertGreaterThan(cell.height, 0)
                }
            }
        }
    }

    /// An unusable aspect lays out oddly rather than not at all: a sheet that
    /// fails to appear is not recoverable, one that looks wrong is.
    func testAnUnusableAspectFallsBackToTheCanvas() {
        let canvas = CGSize(width: 900, height: 600)
        for aspect in [0.0, -2.0, Double.nan, Double.infinity] {
            let cells = layout(cols: 3, rows: 2, gap: 0, cellAspect: aspect, canvas: canvas)
            XCTAssertEqual(cells.count, 6, "aspect \(aspect)")
            XCTAssertEqual(cells[2].maxX, Double(canvas.width), accuracy: epsilon, "aspect \(aspect)")
        }
    }

    func testASingleCell() {
        let cells = layout(cols: 1, rows: 1, gap: 20, cellAspect: 1, canvas: CGSize(width: 500, height: 400))
        XCTAssertEqual(cells.count, 1)
        XCTAssertEqual(cells[0].width, 360, accuracy: epsilon)   // 400 − 2 × 20, height binds
        XCTAssertEqual(cells[0].height, 360, accuracy: epsilon)
        XCTAssertEqual(cells[0].midX, 250, accuracy: epsilon)
        XCTAssertEqual(cells[0].midY, 200, accuracy: epsilon)
    }

    // MARK: - Linearity

    /// The property M5 depends on. Printing applies a single uniform scale to
    /// the rectangles the window already produced; if the geometry is linear,
    /// that transform is exact by construction and the printed sheet cannot
    /// drift from the screen. Worth pinning three milestones early.
    func testDoublingTheCanvasAndTheGapDoublesEveryRectangle() {
        let canvas = CGSize(width: 1131, height: 707)
        let single = layout(cols: 5, rows: 4, gap: 11, cellAspect: 1, canvas: canvas)
        let doubled = layout(cols: 5, rows: 4, gap: 22, cellAspect: 1,
                             canvas: CGSize(width: canvas.width * 2, height: canvas.height * 2))

        XCTAssertEqual(single.count, doubled.count)
        for (a, b) in zip(single, doubled) {
            XCTAssertEqual(b.minX, a.minX * 2, accuracy: 1e-8)
            XCTAssertEqual(b.minY, a.minY * 2, accuracy: 1e-8)
            XCTAssertEqual(b.width, a.width * 2, accuracy: 1e-8)
            XCTAssertEqual(b.height, a.height * 2, accuracy: 1e-8)
        }
    }

    func testTheSameHoldsForAnArbitraryScaleFactor() {
        let scale = 3.7
        let canvas = CGSize(width: 800, height: 640)
        let single = layout(cols: 3, rows: 3, gap: 5, cellAspect: 1.5, canvas: canvas)
        let scaled = layout(cols: 3, rows: 3, gap: 5 * scale, cellAspect: 1.5,
                            canvas: CGSize(width: canvas.width * scale, height: canvas.height * scale))

        for (a, b) in zip(single, scaled) {
            XCTAssertEqual(b.minX, a.minX * scale, accuracy: 1e-7)
            XCTAssertEqual(b.width, a.width * scale, accuracy: 1e-7)
        }
    }
}
