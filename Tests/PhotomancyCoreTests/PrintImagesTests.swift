import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PhotomancyCore

/// Real files, through the real bookmark resolver and the real decoder. The
/// print path's whole job is to read originals rather than anything cached, so
/// a mock here would test the wrong thing.
final class PrintImagesTests: XCTestCase {

    private var directory: URL!
    private var resolver: BookmarkResolver!

    override func setUpWithError() throws {
        directory = try TestImages.temporaryDirectory()
        resolver = BookmarkResolver()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let canvas = CGSize(width: 1600, height: 700)
    private let settings = SheetSettings(columns: 5, rows: 4, gap: 12)

    private var printable: CGRect {
        let margin = 6.35 / 25.4 * 72
        let page = Paper(size: .a4, orientation: .landscape).points
        return CGRect(x: margin, y: margin,
                      width: page.width - 2 * margin,
                      height: page.height - 2 * margin)
    }

    private func geometry(aspect: Double = 1) -> SheetGeometry {
        sheetGeometry(settings: settings, cellAspect: aspect, canvas: canvas)
    }

    /// Every photograph must be a *different* photograph.
    ///
    /// `TestImages.makeCGImage` draws the same gradient at any given size, so
    /// two files written from it are byte-identical and therefore the same
    /// photograph — a content hash is the identity, by design. The resolver
    /// caches resolutions by that hash, so a test that deletes one of two
    /// identical files finds the survivor's URL under the same key and nothing
    /// looks missing. Widening each successive file by a few pixels is enough
    /// to keep them distinct.
    private var written = 0

    @discardableResult
    private func photograph(_ name: String, width: Int = 2400, height: Int = 1600) throws -> PhotoReference {
        written += 1
        let image = try TestImages.makeCGImage(width: width + written, height: height)
        let url = try TestImages.write(image, as: .jpeg, to: directory.appendingPathComponent(name))
        return try Importer.makeReference(for: url)
    }

    /// Something that compresses like a photograph: smooth structure with
    /// grain over it. The flat colour blocks `TestImages` draws are the one
    /// kind of picture where lossless beats JPEG — Flate crushes 5 MB of
    /// samples to 22 KB — so measuring a PDF with them would measure the
    /// opposite of what a photograph does.
    private func photographicImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let grain = Double((seed >> 33) & 0xFF) / 255 * 28 - 14
                let u = Double(x) / Double(width), v = Double(y) / Double(height)
                func byte(_ value: Double) -> UInt8 { UInt8(min(max(value + grain, 0), 255)) }
                let offset = (y * width + x) * 4
                pixels[offset] = byte(128 + 100 * sin(u * 6.3) * cos(v * 3.1))
                pixels[offset + 1] = byte(128 + 90 * cos(u * 4.1 + v * 2.7))
                pixels[offset + 2] = byte(128 + 80 * sin(v * 5.5))
            }
        }
        var image: CGImage?
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return }
            image = context.makeImage()
        }
        return try XCTUnwrap(image)
    }

    // MARK: - The size to decode

    /// 72 points to the inch, so 360 ppi is five pixels a point.
    func testTheLongEdgeIsFivePixelsPerPointAtThreeSixtyPPI() {
        XCTAssertEqual(PrintImages.pixels(forPhotographDrawnAt: CGSize(width: 100, height: 50),
                                          originalLongEdge: 10_000), 500)
        XCTAssertEqual(PrintImages.pixels(forPhotographDrawnAt: CGSize(width: 50, height: 100),
                                          originalLongEdge: 10_000), 500, "the long edge, whichever it is")
    }

    /// The figure the plan quotes: a 45 mm cell wants about 640 px.
    func testAFortyFiveMillimetreFrameWantsAboutSixHundredAndFortyPixels() {
        let points = 45.1 / 25.4 * 72
        let pixels = PrintImages.pixels(forPhotographDrawnAt: CGSize(width: points, height: points),
                                        originalLongEdge: 10_000)
        XCTAssertEqual(Double(pixels), 639, accuracy: 2)
    }

    /// ImageIO does not enlarge, so asking past the original only wastes the
    /// request — and would store a second copy of the same pixels.
    func testTheRequestIsCappedAtTheOriginal() {
        XCTAssertEqual(PrintImages.pixels(forPhotographDrawnAt: CGSize(width: 1000, height: 1000),
                                          originalLongEdge: 1600), 1600)
        XCTAssertEqual(PrintImages.pixels(forPhotographDrawnAt: CGSize(width: 1000, height: 1000),
                                          originalLongEdge: 0), 5000, "an unknown original is not a cap")
    }

    func testAnUnusableDrawnSizeAsksForSomethingRatherThanNothing() {
        for size in [CGSize.zero, CGSize(width: -10, height: -10), CGSize(width: CGFloat.nan, height: 5)] {
            XCTAssertEqual(PrintImages.pixels(forPhotographDrawnAt: size, originalLongEdge: 4000), 1,
                           "size \(size)")
        }
    }

    func testResolutionIsAParameterAndThreeSixtyIsItsDefault() {
        XCTAssertEqual(PrintImages.pixelsPerInch, 360)
        XCTAssertEqual(PrintImages.pixels(forPhotographDrawnAt: CGSize(width: 72, height: 72),
                                          originalLongEdge: 10_000), 360)
        XCTAssertEqual(PrintImages.pixels(forPhotographDrawnAt: CGSize(width: 72, height: 72),
                                          originalLongEdge: 10_000, pixelsPerInch: 300), 300)
    }

    // MARK: - Decoding for a page

    func testEachPhotographIsDecodedAtTheSizeItPrints() throws {
        let geometry = self.geometry()
        let placements = [
            PrintImages.Placement(cell: 0, reference: try photograph("a.jpg")),
            PrintImages.Placement(cell: 1, reference: try photograph("b.jpg")),
        ]
        let frames = try PrintImages.frames(for: placements, geometry: geometry,
                                            printable: printable, resolver: resolver)

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames.map(\.cell), [0, 1])

        // A square cell of about 45 mm holding a 3:2 frame: the frame spans the
        // cell's width, so its long edge is the cell's, about 640 px.
        for frame in frames {
            let longEdge = max(frame.image.width, frame.image.height)
            XCTAssertEqual(Double(longEdge), 639, accuracy: 4, "decoded for paper, not for a screen")
        }
    }

    /// Bigger paper is more pixels. This is why the decode waits for the paper
    /// the panel actually ends on instead of running before it opens.
    func testTheSamePhotographDecodesLargerOnLargerPaper() throws {
        let geometry = self.geometry()
        let placements = [PrintImages.Placement(cell: 0, reference: try photograph("a.jpg"))]

        func longEdge(onto printable: CGRect) throws -> Int {
            let frames = try PrintImages.frames(for: placements, geometry: geometry,
                                                printable: printable, resolver: resolver)
            return max(frames[0].image.width, frames[0].image.height)
        }
        let doubled = CGRect(x: printable.minX, y: printable.minY,
                             width: printable.width * 2, height: printable.height * 2)
        XCTAssertEqual(try longEdge(onto: doubled), try longEdge(onto: printable) * 2, accuracy: 3)
    }

    func testNothingIsAskedForACellThatIsNotOnTheSheet() throws {
        let geometry = self.geometry()   // 20 cells
        let frames = try PrintImages.frames(
            for: [PrintImages.Placement(cell: 99, reference: try photograph("a.jpg")),
                  PrintImages.Placement(cell: 4, reference: try photograph("b.jpg"))],
            geometry: geometry, printable: printable, resolver: resolver
        )
        XCTAssertEqual(frames.map(\.cell), [4])
    }

    func testASheetThatHasNotLaidOutDecodesNothing() throws {
        let frames = try PrintImages.frames(
            for: [PrintImages.Placement(cell: 0, reference: try photograph("a.jpg"))],
            geometry: .empty, printable: printable, resolver: resolver
        )
        XCTAssertTrue(frames.isEmpty)
    }

    // MARK: - A photograph that cannot be read

    /// On paper a missing photograph would be indistinguishable from an empty
    /// cell, so the sheet would come out quietly short a frame.
    func testAMissingPhotographStopsTheJobAndNamesIt() throws {
        let present = try photograph("here.jpg")
        let gone = try photograph("DSCF5698.jpg")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("DSCF5698.jpg"))

        XCTAssertThrowsError(try PrintImages.frames(
            for: [PrintImages.Placement(cell: 0, reference: present),
                  PrintImages.Placement(cell: 1, reference: gone)],
            geometry: geometry(), printable: printable, resolver: resolver
        )) { error in
            guard let missing = error as? PrintImages.PhotographsMissing else {
                return XCTFail("expected PhotographsMissing, got \(error)")
            }
            XCTAssertEqual(missing.names, ["DSCF5698.jpg"])
            XCTAssertEqual(missing.errorDescription, "“DSCF5698.jpg” can’t be found.")
        }
    }

    func testEveryMissingPhotographIsNamedInOneGoAndInSheetOrder() throws {
        var placements: [PrintImages.Placement] = []
        for (index, name) in ["one.jpg", "two.jpg", "three.jpg"].enumerated() {
            placements.append(PrintImages.Placement(cell: index, reference: try photograph(name)))
            try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }

        XCTAssertThrowsError(try PrintImages.frames(for: placements.reversed(), geometry: geometry(),
                                                    printable: printable, resolver: resolver)) { error in
            let missing = error as? PrintImages.PhotographsMissing
            XCTAssertEqual(missing?.names, ["one.jpg", "two.jpg", "three.jpg"],
                           "named in cell order, whatever order they were handed over in")
            XCTAssertEqual(missing?.errorDescription,
                           "3 photographs can’t be found: one.jpg, two.jpg, three.jpg.")
        }
    }

    func testALongListOfMissingPhotographsIsNamedAndThenCounted() {
        let many = PrintImages.PhotographsMissing(names: (1...9).map { "frame\($0).jpg" })
        XCTAssertEqual(many.errorDescription,
                       "9 photographs can’t be found: frame1.jpg, frame2.jpg, frame3.jpg, and 6 more.")
        XCTAssertNotNil(many.recoverySuggestion)
    }

    /// Checked before anything is decoded: a job with a missing file must fail
    /// at once rather than after spending a second on the others.
    func testTheCheckHappensBeforeAnyDecoding() throws {
        var placements: [PrintImages.Placement] = []
        for index in 0..<8 {
            placements.append(PrintImages.Placement(cell: index, reference: try photograph("p\(index).jpg", width: 4000, height: 3000)))
        }
        let gone = try photograph("gone.jpg")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("gone.jpg"))
        placements.append(PrintImages.Placement(cell: 8, reference: gone))

        let started = Date()
        XCTAssertThrowsError(try PrintImages.frames(for: placements, geometry: geometry(),
                                                    printable: printable, resolver: resolver))
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.25,
                          "eight 12 MP originals were not decoded before the job gave up")
    }

    // MARK: - What the PDF carries

    func testAPhotographIsCarriedAsJPEGSoAPDFHoldsItCompressed() throws {
        let image = try photographicImage(width: 1300, height: 1300)
        let asJPEG = try XCTUnwrap(PrintImages.compressed(image))

        XCTAssertEqual(asJPEG.width, image.width, "the same picture, at the same size")
        XCTAssertEqual(asJPEG.height, image.height)

        let compressed = pdfBytes(drawing: asJPEG)
        let raw = pdfBytes(drawing: image)
        XCTAssertLessThan(compressed, raw / 2,
                          "step 0 measured 36.0 MB against 7.4 MB on twenty real photographs; "
                          + "here \(raw) against \(compressed)")
    }

    /// The identity assumption the fixtures rest on, asserted rather than
    /// assumed: two photographs in a test are two photographs.
    func testTheFixturesProduceDistinctPhotographs() throws {
        let one = try photograph("one.jpg")
        let two = try photograph("two.jpg")
        XCTAssertNotEqual(one.id, two.id, "identical bytes would be one photograph, not two")
    }

    func testTheFramesHandedBackAreTheCompressedOnes() throws {
        let frames = try PrintImages.frames(
            for: [PrintImages.Placement(cell: 0, reference: try photograph("a.jpg"))],
            geometry: geometry(), printable: printable, resolver: resolver
        )
        let frame = try XCTUnwrap(frames.first)
        // A JPEG-backed image reports itself as such through its UTType.
        XCTAssertEqual(frame.image.utType, UTType.jpeg.identifier as CFString)
    }

    private func pdfBytes(drawing image: CGImage) -> Int {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 600, height: 600)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return 0 }
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()
        return data.length
    }

    // MARK: - Not the thumbnail cache

    /// The print path reads originals and leaves no trace in the caches the
    /// grid uses. A print job's images are far larger than anything a cell
    /// wants, and writing them through would evict the whole warm cache for
    /// pictures nobody looks at again.
    func testPrintingWritesNothingToTheThumbnailCaches() throws {
        let cacheDirectory = directory.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let cache = ThumbnailCache(resolver: resolver, directory: cacheDirectory)

        _ = try PrintImages.frames(
            for: [PrintImages.Placement(cell: 0, reference: try photograph("a.jpg")),
                  PrintImages.Placement(cell: 1, reference: try photograph("b.jpg"))],
            geometry: geometry(), printable: printable, resolver: resolver
        )

        let written = try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)
        XCTAssertTrue(written.isEmpty, "the disk cache is untouched, found: \(written)")
        XCTAssertEqual(cache.statistics, ThumbnailCache.Statistics(), "and nothing went through the cache at all")
    }
}
