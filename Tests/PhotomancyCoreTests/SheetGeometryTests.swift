import XCTest
import CoreGraphics
@testable import PhotomancyCore

/// The screen and the page share one geometry, so this is where it is proved
/// that they cannot come apart. None of it needs a window or an eye.
final class SheetGeometryTests: XCTestCase {

    private let epsilon = 1e-9

    /// The plan's worked example: a wide window, square cells, A4 landscape.
    private let exampleCanvas = CGSize(width: 1600, height: 700)
    private let exampleSettings = SheetSettings(columns: 5, rows: 4, gap: 12)

    /// A4 landscape, less 6.35 mm of printer margin all round, in points.
    private var exampleprintable: CGRect {
        let margin = 6.35 / 25.4 * 72
        let page = Paper(size: .a4, orientation: .landscape).points
        return CGRect(x: margin, y: margin,
                      width: page.width - 2 * margin,
                      height: page.height - 2 * margin)
    }

    // MARK: - One geometry

    func testTheCellsAreExactlyWhatLayoutReturnsAtTheGapUsed() {
        let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: exampleCanvas)
        let direct = layout(cols: 5, rows: 4, gap: geometry.gap, cellAspect: 1, canvas: exampleCanvas)
        XCTAssertEqual(geometry.cells, direct)
        XCTAssertEqual(geometry.cells.count, 20)
    }

    func testAnOrdinaryWindowLaysOutAtTheStoredGap() {
        let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: exampleCanvas)
        XCTAssertEqual(geometry.gap, 12, accuracy: epsilon)
    }

    /// The case the shared function exists for: a window too small for the
    /// stored gap. The screen already clamped; now the page clamps identically.
    func testAWindowTooSmallForTheStoredGapClampsRatherThanGoingBlank() {
        let settings = SheetSettings(columns: 8, rows: 8, gap: 40)
        let canvas = CGSize(width: 300, height: 300)
        let geometry = sheetGeometry(settings: settings, cellAspect: 1, canvas: canvas)

        XCTAssertLessThan(geometry.gap, 40)
        XCTAssertEqual(geometry.gap, maximumGap(cols: 8, rows: 8, canvas: canvas), accuracy: epsilon)
        XCTAssertEqual(geometry.cells.count, 64, "the sheet still lays out")
        XCTAssertFalse(geometry.block.isEmpty)
    }

    // MARK: - The block

    func testTheBlockIsTheCellsPlusTheGapAllRound() {
        let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: exampleCanvas)
        let cell = try? XCTUnwrap(geometry.cells.first)
        let gap = geometry.gap

        XCTAssertEqual(geometry.block.width, 5 * (cell?.width ?? 0) + 6 * gap, accuracy: 1e-9)
        XCTAssertEqual(geometry.block.height, 4 * (cell?.height ?? 0) + 5 * gap, accuracy: 1e-9)
        XCTAssertEqual(geometry.block.minX, (cell?.minX ?? 0) - gap, accuracy: epsilon)
        XCTAssertEqual(geometry.block.minY, (cell?.minY ?? 0) - gap, accuracy: epsilon)
    }

    func testTheBlockContainsEveryCellAndNeverLeavesTheCanvas() {
        for aspect in [1.0, 1.5, 3.0 / 4.0, 2.5] {
            for canvas in [CGSize(width: 1600, height: 700), CGSize(width: 600, height: 1400), CGSize(width: 900, height: 900)] {
                let geometry = sheetGeometry(settings: exampleSettings, cellAspect: aspect, canvas: canvas)
                let whole = CGRect(origin: .zero, size: canvas)
                for cell in geometry.cells {
                    XCTAssertTrue(geometry.block.insetBy(dx: -epsilon, dy: -epsilon).contains(cell),
                                  "aspect \(aspect) canvas \(canvas)")
                }
                XCTAssertTrue(whole.insetBy(dx: -1e-6, dy: -1e-6).contains(geometry.block),
                              "the block is dead space away from the window's edge, never past it")
            }
        }
    }

    /// The block carries its own outer margin, so on the binding axis it spans
    /// the window exactly and the dead space is all on the other one.
    func testTheBlockSpansTheBindingAxisExactly() {
        let wide = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: exampleCanvas)
        XCTAssertEqual(wide.block.height, exampleCanvas.height, accuracy: 1e-9, "height binds in a wide window")
        XCTAssertLessThan(wide.block.width, exampleCanvas.width)

        let tall = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: CGSize(width: 600, height: 1400))
        XCTAssertEqual(tall.block.width, 600, accuracy: 1e-9, "width binds in a tall window")
        XCTAssertLessThan(tall.block.height, 1400)
    }

    func testAWindowWithNoSizeYetHasNoGeometryRatherThanNonsense() {
        for canvas in [CGSize.zero, CGSize(width: 1200, height: 0), CGSize(width: CGFloat.nan, height: 800)] {
            let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: canvas)
            XCTAssertTrue(geometry.cells.isEmpty, "canvas \(canvas)")
            XCTAssertEqual(geometry.block, CGRect.zero)
            XCTAssertEqual(geometry.gap, 0)
        }
    }

    func testAStoredGapThatIsNotANumberLaysOutAtZeroRatherThanSpreadingNaN() {
        var settings = exampleSettings
        settings.gap = .nan
        let geometry = sheetGeometry(settings: settings, cellAspect: 1, canvas: exampleCanvas)

        XCTAssertEqual(geometry.gap, 0)
        XCTAssertEqual(geometry.cells.count, 20)
        XCTAssertTrue(geometry.block.width.isFinite)
        XCTAssertTrue(geometry.block.height.isFinite)
    }

    // MARK: - The transform

    func testTheBlockLandsInsideThePrintableAreaAndIsCentred() {
        let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: exampleCanvas)
        let printable = exampleprintable
        let printed = geometry.block.applying(pageTransform(from: geometry.block, onto: printable))

        XCTAssertTrue(printable.insetBy(dx: -1e-6, dy: -1e-6).contains(printed))
        // Centred: the slack is equal on both sides of whichever axis has any.
        XCTAssertEqual(printed.minX - printable.minX, printable.maxX - printed.maxX, accuracy: 1e-9)
        XCTAssertEqual(printed.minY - printable.minY, printable.maxY - printed.maxY, accuracy: 1e-9)
    }

    func testTheBlockTouchesTheEdgesOfTheAxisThatBinds() {
        let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: exampleCanvas)
        let printable = exampleprintable
        let printed = geometry.block.applying(pageTransform(from: geometry.block, onto: printable))

        // 872 × 700 onto 805.9 × 559.3 pt: height binds.
        XCTAssertEqual(printed.height, printable.height, accuracy: 1e-9)
        XCTAssertLessThan(printed.width, printable.width)
    }

    func testTheScaleIsUniformSoACellKeepsItsShapeOnPaper() {
        for aspect in [1.0, 1.5, 3.0 / 4.0] {
            for paper in [Paper(size: .a4, orientation: .landscape),
                          Paper(size: .a4, orientation: .portrait),
                          Paper(size: .usLetter, orientation: .portrait)] {
                let geometry = sheetGeometry(settings: exampleSettings, cellAspect: aspect, canvas: exampleCanvas)
                let printable = CGRect(origin: .zero, size: paper.points).insetBy(dx: 18, dy: 18)
                let transform = pageTransform(from: geometry.block, onto: printable)
                let cell = try? XCTUnwrap(geometry.cells.first)
                let printedCell = (cell ?? .zero).applying(transform)

                XCTAssertEqual(printedCell.width / printedCell.height,
                               (cell?.width ?? 1) / (cell?.height ?? 1),
                               accuracy: 1e-9, "aspect \(aspect) on \(paper.size)")
                XCTAssertEqual(transform.a, -transform.d, accuracy: 1e-12, "same scale in x and y")
                XCTAssertEqual(transform.b, 0)
                XCTAssertEqual(transform.c, 0)
            }
        }
    }

    /// Every proportion the window had, the page has. This is the whole claim of
    /// "exact by construction", so it is checked on every pair of rectangles.
    func testEveryProportionOfTheSheetSurvivesTheTransform() {
        let geometry = sheetGeometry(settings: SheetSettings(columns: 4, rows: 3, gap: 9),
                                     cellAspect: 3.0 / 2.0,
                                     canvas: CGSize(width: 1400, height: 950))
        let transform = pageTransform(from: geometry.block, onto: exampleprintable)
        let printed = geometry.cells.map { $0.applying(transform) }
        let scale = transform.a

        for (cell, page) in zip(geometry.cells, printed) {
            XCTAssertEqual(page.width, cell.width * scale, accuracy: 1e-9)
            XCTAssertEqual(page.height, cell.height * scale, accuracy: 1e-9)
        }
        // Distances between cells scale by the same factor, so the gaps do too.
        for index in 1..<printed.count {
            XCTAssertEqual(printed[index].minX - printed[0].minX,
                           (geometry.cells[index].minX - geometry.cells[0].minX) * scale, accuracy: 1e-9)
            XCTAssertEqual(printed[0].minY - printed[index].minY,
                           (geometry.cells[index].minY - geometry.cells[0].minY) * scale, accuracy: 1e-9)
        }
    }

    // MARK: - The flip

    func testCellZeroLandsAtTheTopLeftOfThePage() {
        let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: exampleCanvas)
        let transform = pageTransform(from: geometry.block, onto: exampleprintable)
        let printed = geometry.cells.map { $0.applying(transform) }

        let leftmost = printed.map(\.minX).min() ?? 0
        let highest = printed.map(\.maxY).max() ?? 0
        XCTAssertEqual(printed[0].minX, leftmost, accuracy: 1e-9)
        XCTAssertEqual(printed[0].maxY, highest, accuracy: 1e-9, "Quartz counts y upward — the top row has the largest y")

        // And the last cell is the opposite corner.
        let last = printed[printed.count - 1]
        XCTAssertEqual(last.maxX, printed.map(\.maxX).max() ?? 0, accuracy: 1e-9)
        XCTAssertEqual(last.minY, printed.map(\.minY).min() ?? 0, accuracy: 1e-9)
    }

    func testRowsDescendThePageAndColumnsRunLeftToRight() {
        let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: exampleCanvas)
        let transform = pageTransform(from: geometry.block, onto: exampleprintable)
        let printed = geometry.cells.map { $0.applying(transform) }

        for column in 1..<5 {
            XCTAssertGreaterThan(printed[column].minX, printed[column - 1].minX, "column \(column)")
            XCTAssertEqual(printed[column].minY, printed[0].minY, accuracy: 1e-9, "one row shares a y")
        }
        for row in 1..<4 {
            XCTAssertLessThan(printed[row * 5].minY, printed[(row - 1) * 5].minY, "row \(row) is lower on the page")
        }
    }

    func testADegenerateBlockOrPageYieldsTheIdentityRatherThanTrapping() {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        XCTAssertEqual(pageTransform(from: CGRect.zero, onto: page), .identity)
        XCTAssertEqual(pageTransform(from: CGRect(x: 0, y: 0, width: 100, height: 100), onto: CGRect.zero), .identity)
        XCTAssertEqual(pageTransform(from: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100), onto: page), .identity)
    }

    // MARK: - Print metrics

    /// The figure the plan quotes, reproduced from the code: a 1600 × 700 pt
    /// window, 5 × 4 square cells, 12 px gap, on A4 landscape with 6.35 mm
    /// margins, prints 45.1 mm cells at a 3.4 mm gap.
    func testThePlansWorkedExampleReproduces() {
        let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: exampleCanvas)
        let metrics = try? XCTUnwrap(printMetrics(for: geometry, onto: exampleprintable))

        XCTAssertEqual(metrics?.cell.width ?? 0, 45.1, accuracy: 0.05)
        XCTAssertEqual(metrics?.cell.height ?? 0, 45.1, accuracy: 0.05)
        XCTAssertEqual(metrics?.gap ?? 0, 3.4, accuracy: 0.05)
        XCTAssertEqual(metrics?.summary, "Cells 45.1 × 45.1 mm · gap 3.4 mm")
    }

    /// Scaling the whole window instead — what is *not* built — makes the same
    /// photographs 28.4 mm. The block is the composition; the dead space is not.
    func testScalingTheWindowWouldPrintTheSameSheetMuchSmaller() {
        let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: exampleCanvas)
        let window = CGRect(origin: .zero, size: exampleCanvas)
        let scale = pageTransform(from: window, onto: exampleprintable).a
        let cell = (geometry.cells.first?.width ?? 0) * scale * 25.4 / 72

        XCTAssertEqual(cell, 28.4, accuracy: 0.05)
        XCTAssertLessThan(cell, 45.1, "which is why the block is what gets scaled")
    }

    func testTheMetricsScaleIsTheTransformThatDraws() {
        let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: exampleCanvas)
        let printable = exampleprintable
        let metrics = try? XCTUnwrap(printMetrics(for: geometry, onto: printable))
        XCTAssertEqual(metrics?.scale ?? 0, pageTransform(from: geometry.block, onto: printable).a, accuracy: 1e-12)
    }

    /// The gap is proportional on paper, not absolute — this is the contract's
    /// formula, `gap ÷ block width × printed block width`, checked directly.
    func testThePrintedGapIsTheSameShareOfTheBlockItIsOnScreen() {
        let printable = exampleprintable
        for canvas in [CGSize(width: 1600, height: 700), CGSize(width: 700, height: 700), CGSize(width: 620, height: 1500)] {
            let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: canvas)
            let metrics = try? XCTUnwrap(printMetrics(for: geometry, onto: printable))
            let printedBlock = geometry.block.applying(pageTransform(from: geometry.block, onto: printable))
            let printedBlockMillimetres = printedBlock.width * 25.4 / 72

            XCTAssertEqual((metrics?.gap ?? 0) / printedBlockMillimetres,
                           geometry.gap / geometry.block.width,
                           accuracy: 1e-12, "canvas \(canvas)")
        }
    }

    /// And so the same stored 12 px is a different physical measure once the
    /// window is reshaped enough to change which axis binds.
    func testReshapingTheWindowChangesTheMillimetresOnPaper() {
        let printable = exampleprintable
        let wide = printMetrics(for: sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: CGSize(width: 1600, height: 700)),
                                onto: printable)
        let square = printMetrics(for: sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: CGSize(width: 700, height: 700)),
                                  onto: printable)

        XCTAssertEqual(wide?.gap ?? 0, 3.38, accuracy: 0.01)
        XCTAssertEqual(square?.gap ?? 0, 4.21, accuracy: 0.01,
                       "a squarer window fits fewer cells across, so each one's share of the paper is larger")
    }

    /// Twice the printable area is twice everything, which is what "one uniform
    /// scale" means when the paper changes.
    func testDoublingThePrintableAreaDoublesEveryPrintedMeasure() {
        let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: exampleCanvas)
        let printable = exampleprintable
        let doubled = CGRect(x: printable.minX * 2, y: printable.minY * 2,
                             width: printable.width * 2, height: printable.height * 2)

        let once = try? XCTUnwrap(printMetrics(for: geometry, onto: printable))
        let twice = try? XCTUnwrap(printMetrics(for: geometry, onto: doubled))
        XCTAssertEqual(twice?.cell.width ?? 0, (once?.cell.width ?? 0) * 2, accuracy: 1e-9)
        XCTAssertEqual(twice?.gap ?? 0, (once?.gap ?? 0) * 2, accuracy: 1e-9)
    }

    /// A wide sheet on A4: landscape prints it half again as large as portrait.
    /// Paper is remembered per collection because this is the size of the
    /// difference.
    func testOrientationDecidesHowLargeTheSheetPrints() {
        let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: exampleCanvas)
        func cellMillimetres(_ paper: Paper) -> Double {
            let printable = CGRect(origin: .zero, size: paper.points).insetBy(dx: 18, dy: 18)
            return Double(printMetrics(for: geometry, onto: printable)?.cell.width ?? 0)
        }
        XCTAssertGreaterThan(cellMillimetres(Paper(size: .a4, orientation: .landscape)),
                             cellMillimetres(Paper(size: .a4, orientation: .portrait)))
    }

    func testThereAreNoMetricsForASheetThatHasNotLaidOutYet() {
        XCTAssertNil(printMetrics(for: .empty, onto: exampleprintable))
        let geometry = sheetGeometry(settings: exampleSettings, cellAspect: 1, canvas: exampleCanvas)
        XCTAssertNil(printMetrics(for: geometry, onto: CGRect.zero))
    }
}
