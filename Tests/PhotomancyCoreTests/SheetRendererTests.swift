import XCTest
import CoreGraphics
@testable import PhotomancyCore

/// The renderer is checked by reading the pixels it produced, not by trusting
/// the arithmetic that put them there. Solid-colour photographs make that a
/// question with one answer: what colour is the paper at this point?
final class SheetRendererTests: XCTestCase {

    // Distinct enough that no resample or colour conversion can confuse them.
    private let paper = SheetColor(red: 1, green: 1, blue: 0)      // yellow: untouched page
    private let sheetBackground = SheetColor(red: 0, green: 0, blue: 1) // blue: the sheet
    private let red = SheetColor(red: 1, green: 0, blue: 0)
    private let green = SheetColor(red: 0, green: 1, blue: 0)

    private let canvas = CGSize(width: 1600, height: 700)
    private let settings = SheetSettings(columns: 5, rows: 4, gap: 12)

    /// A4 landscape less 6.35 mm of printer margin, in points.
    private var printable: CGRect {
        let margin = 6.35 / 25.4 * 72
        let page = Paper(size: .a4, orientation: .landscape).points
        return CGRect(x: margin, y: margin,
                      width: page.width - 2 * margin,
                      height: page.height - 2 * margin)
    }

    private var pageRect: CGRect {
        CGRect(origin: .zero, size: Paper(size: .a4, orientation: .landscape).points)
    }

    private func geometry(aspect: Double = 1) -> SheetGeometry {
        sheetGeometry(settings: settings, cellAspect: aspect, canvas: canvas)
    }

    // MARK: - A page, rendered and read back

    /// A rendered page whose pixels can be asked about by page point.
    private struct Page {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let scale: Double

        /// The colour at a point in page coordinates — Quartz's, y upward.
        func colour(at point: CGPoint) -> SheetColor {
            let column = Int((point.x * scale).rounded(.down))
            // Row zero of a bitmap's memory is the top of the image, and
            // Quartz counts y from the bottom.
            let row = height - 1 - Int((point.y * scale).rounded(.down))
            guard (0..<width).contains(column), (0..<height).contains(row) else {
                return SheetColor(red: -1, green: -1, blue: -1)
            }
            let offset = row * width * 4 + column * 4
            return SheetColor(
                red: Double(pixels[offset]) / 255,
                green: Double(pixels[offset + 1]) / 255,
                blue: Double(pixels[offset + 2]) / 255
            )
        }
    }

    /// Renders onto a page pre-filled with `paper`, so anything the renderer
    /// does not touch is recognisable as untouched.
    private func render(_ renderer: SheetRenderer, scale: Double = 2) throws -> Page {
        let width = Int((pageRect.width * scale).rounded())
        let height = Int((pageRect.height * scale).rounded())
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { throw XCTSkip("could not create a bitmap context") }

            context.scaleBy(x: scale, y: scale)
            context.setFillColor(paper.cgColor)
            context.fill(pageRect)
            renderer.draw(in: context, onto: printable)
        }
        return Page(pixels: pixels, width: width, height: height, scale: scale)
    }

    private func solid(_ colour: SheetColor, width: Int = 64, height: Int = 64) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw XCTSkip("could not create a bitmap context") }
        context.setFillColor(colour.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw XCTSkip("could not render") }
        return image
    }

    private func assertColour(
        _ actual: SheetColor,
        _ expected: SheetColor,
        _ message: String = "",
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.red, expected.red, accuracy: 0.06, message, line: line)
        XCTAssertEqual(actual.green, expected.green, accuracy: 0.06, message, line: line)
        XCTAssertEqual(actual.blue, expected.blue, accuracy: 0.06, message, line: line)
    }

    /// The centre of a cell, on the page.
    private func centre(ofCell index: Int, _ geometry: SheetGeometry) -> CGPoint {
        let cell = geometry.cells[index].applying(pageTransform(from: geometry.block, onto: printable))
        return CGPoint(x: cell.midX, y: cell.midY)
    }

    // MARK: - What lands where

    func testACellsCentreIsItsPhotographAndTheGapIsBackground() throws {
        let geometry = self.geometry()
        let renderer = SheetRenderer(
            geometry: geometry,
            background: sheetBackground,
            frames: [SheetRenderer.Frame(cell: 0, image: try solid(red)),
                     SheetRenderer.Frame(cell: 1, image: try solid(green))]
        )
        let page = try render(renderer)
        let transform = pageTransform(from: geometry.block, onto: printable)

        assertColour(page.colour(at: centre(ofCell: 0, geometry)), red, "cell 0 holds the red photograph")
        assertColour(page.colour(at: centre(ofCell: 1, geometry)), green, "cell 1 holds the green one")

        // Midway between them is gap, and a gap is background.
        let first = geometry.cells[0].applying(transform)
        let second = geometry.cells[1].applying(transform)
        assertColour(page.colour(at: CGPoint(x: (first.maxX + second.minX) / 2, y: first.midY)),
                     sheetBackground, "the gap between two cells is background")
    }

    func testOutsideTheBlockThePaperIsUntouched() throws {
        let geometry = self.geometry()
        let renderer = SheetRenderer(geometry: geometry, background: sheetBackground,
                                     frames: [SheetRenderer.Frame(cell: 0, image: try solid(red))])
        let page = try render(renderer)
        let block = geometry.block.applying(pageTransform(from: geometry.block, onto: printable))

        // The block is 872 x 700 on a 806 x 559 pt printable area: height binds,
        // so the slack — and the bare paper — is at the left and right.
        assertColour(page.colour(at: CGPoint(x: block.minX - 4, y: block.midY)), paper, "left of the block")
        assertColour(page.colour(at: CGPoint(x: block.maxX + 4, y: block.midY)), paper, "right of the block")
        assertColour(page.colour(at: CGPoint(x: 4, y: 4)), paper, "the corner of the sheet of paper")
        // And just inside it is the sheet.
        assertColour(page.colour(at: CGPoint(x: block.minX + 4, y: block.midY)), sheetBackground, "just inside the block")
    }

    /// The flip, end to end in pixels rather than in arithmetic: the one
    /// photograph on the sheet is in the first cell, and it has to appear at the
    /// top left of the page.
    func testTheFirstCellIsPrintedAtTheTopLeftOfThePage() throws {
        let geometry = self.geometry()
        let renderer = SheetRenderer(geometry: geometry, background: sheetBackground,
                                     frames: [SheetRenderer.Frame(cell: 0, image: try solid(red))])
        let page = try render(renderer)
        let block = geometry.block.applying(pageTransform(from: geometry.block, onto: printable))

        // Near the block's top-left corner, inside the first cell.
        let cell = geometry.cells[0].applying(pageTransform(from: geometry.block, onto: printable))
        XCTAssertLessThan(abs(cell.minX - block.minX) - geometry.gap, 2, "cell 0 sits one gap in from the left")
        assertColour(page.colour(at: CGPoint(x: cell.midX, y: cell.midY)), red, "the photograph is at the top of the page")

        // The opposite corner of the block holds no photograph, so it is background.
        let last = geometry.cells[geometry.cells.count - 1].applying(pageTransform(from: geometry.block, onto: printable))
        assertColour(page.colour(at: CGPoint(x: last.midX, y: last.midY)), sheetBackground,
                     "the bottom right is an empty cell")
        XCTAssertLessThan(last.midY, cell.midY, "and it really is lower on the page")
    }

    /// Not an upside-down sheet, and not an upside-down photograph either: a
    /// two-tone image has to come out the same way up as it went in.
    func testAPhotographIsNotDrawnUpsideDown() throws {
        guard let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw XCTSkip("could not create a bitmap context") }
        // In a bitmap context y runs upward, so this fills the image's own
        // *bottom* half with green and its top half with red.
        context.setFillColor(green.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        context.setFillColor(red.cgColor)
        context.fill(CGRect(x: 0, y: 32, width: 64, height: 32))
        guard let twoTone = context.makeImage() else { throw XCTSkip("could not render") }

        let geometry = self.geometry()
        let renderer = SheetRenderer(geometry: geometry, background: sheetBackground,
                                     frames: [SheetRenderer.Frame(cell: 0, image: twoTone)])
        let page = try render(renderer)
        let cell = geometry.cells[0].applying(pageTransform(from: geometry.block, onto: printable))

        assertColour(page.colour(at: CGPoint(x: cell.midX, y: cell.maxY - cell.height * 0.25)), red,
                     "the image's top stays at the top of the page")
        assertColour(page.colour(at: CGPoint(x: cell.midX, y: cell.minY + cell.height * 0.25)), green,
                     "and its bottom stays at the bottom")
    }

    // MARK: - Fit, and nothing else

    func testAPhotographIsFittedInItsCellRatherThanFillingIt() throws {
        let geometry = self.geometry()   // square cells
        let renderer = SheetRenderer(geometry: geometry, background: sheetBackground,
                                     frames: [SheetRenderer.Frame(cell: 0, image: try solid(red, width: 128, height: 64))])
        let page = try render(renderer)
        let cell = geometry.cells[0].applying(pageTransform(from: geometry.block, onto: printable))

        // A 2:1 frame in a square cell spans the width and leaves a quarter of
        // the cell's height as background above and below.
        assertColour(page.colour(at: CGPoint(x: cell.midX, y: cell.midY)), red, "the frame itself")
        assertColour(page.colour(at: CGPoint(x: cell.minX + 2, y: cell.midY)), red, "and it reaches the cell's edge")
        assertColour(page.colour(at: CGPoint(x: cell.midX, y: cell.maxY - 2)), sheetBackground,
                     "background above — never cropped to fill")
        assertColour(page.colour(at: CGPoint(x: cell.midX, y: cell.minY + 2)), sheetBackground, "and below")
    }

    func testAnEmptyCellIsBackgroundAndNothingElse() throws {
        let geometry = self.geometry()
        let renderer = SheetRenderer(geometry: geometry, background: sheetBackground, frames: [])
        let page = try render(renderer)

        // No outline, no placeholder, no hint that a cell is there: every point
        // across a cell and its gaps is the one colour.
        let cell = geometry.cells[7].applying(pageTransform(from: geometry.block, onto: printable))
        for point in [CGPoint(x: cell.midX, y: cell.midY),
                      CGPoint(x: cell.minX + 1, y: cell.midY),
                      CGPoint(x: cell.maxX - 1, y: cell.midY),
                      CGPoint(x: cell.midX, y: cell.minY + 1),
                      CGPoint(x: cell.midX, y: cell.maxY - 1),
                      CGPoint(x: cell.minX - 4, y: cell.midY)] {
            assertColour(page.colour(at: point), sheetBackground, "at \(point)")
        }
    }

    func testTheBackgroundIsDrawnEvenWithNoPhotographsAtAll() throws {
        let geometry = self.geometry()
        let page = try render(SheetRenderer(geometry: geometry, background: sheetBackground, frames: []))
        let block = geometry.block.applying(pageTransform(from: geometry.block, onto: printable))
        assertColour(page.colour(at: CGPoint(x: block.midX, y: block.midY)), sheetBackground)
        assertColour(page.colour(at: CGPoint(x: block.minX - 4, y: block.midY)), paper)
    }

    // MARK: - Nothing to draw

    func testASheetThatHasNotLaidOutDrawsNothingAtAll() throws {
        let renderer = SheetRenderer(geometry: .empty, background: sheetBackground,
                                     frames: [SheetRenderer.Frame(cell: 0, image: try solid(red))])
        let page = try render(renderer)
        assertColour(page.colour(at: CGPoint(x: pageRect.midX, y: pageRect.midY)), paper,
                     "no geometry, no ink")
    }

    func testAFrameForACellThatIsNotOnTheSheetIsIgnored() throws {
        let geometry = self.geometry()   // 20 cells
        let renderer = SheetRenderer(
            geometry: geometry,
            background: sheetBackground,
            frames: [SheetRenderer.Frame(cell: 99, image: try solid(red)),
                     SheetRenderer.Frame(cell: -1, image: try solid(red)),
                     SheetRenderer.Frame(cell: 3, image: try solid(green))]
        )
        let page = try render(renderer)
        assertColour(page.colour(at: centre(ofCell: 3, geometry)), green, "the one real frame is drawn")
        for index in [0, 1, 2, 4, 19] {
            assertColour(page.colour(at: centre(ofCell: index, geometry)), sheetBackground,
                         "cell \(index) stays empty rather than catching a stray frame")
        }
    }

    // MARK: - A PDF page

    func testAPDFContextGivesOnePageOfTheRightSize() throws {
        let geometry = self.geometry()
        let renderer = SheetRenderer(geometry: geometry, background: sheetBackground,
                                     frames: [SheetRenderer.Frame(cell: 0, image: try solid(red))])

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw XCTSkip("no data consumer") }
        var mediaBox = pageRect
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw XCTSkip("no PDF context")
        }
        context.beginPDFPage(nil)
        renderer.draw(in: context, onto: printable)
        context.endPDFPage()
        context.closePDF()

        XCTAssertGreaterThan(data.length, 0)
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else { throw XCTSkip("could not read the PDF back") }

        XCTAssertEqual(document.numberOfPages, 1, "one page, and no pagination")
        let box = try XCTUnwrap(document.page(at: 1)?.getBoxRect(.mediaBox))
        XCTAssertEqual(box.width, pageRect.width, accuracy: 0.5, "A4 landscape, 842 x 595 pt")
        XCTAssertEqual(box.height, pageRect.height, accuracy: 0.5)
    }

    // MARK: - What the renderer will do, before it does it

    func testTheRendererReportsTheSameTransformItDrawsWith() {
        let geometry = self.geometry()
        let renderer = SheetRenderer(geometry: geometry, background: sheetBackground, frames: [])
        XCTAssertEqual(renderer.transform(onto: printable), pageTransform(from: geometry.block, onto: printable))
        XCTAssertEqual(renderer.transform(onto: printable).a,
                       printMetrics(for: geometry, onto: printable)?.scale ?? 0, accuracy: 1e-12,
                       "the panel's millimetres describe this drawing and no other")
    }
}
