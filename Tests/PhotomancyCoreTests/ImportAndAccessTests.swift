import XCTest
import UniformTypeIdentifiers
@testable import PhotomancyCore

/// Import, bookmark, and read back through the resolver.
///
/// Read the limit of these honestly: within one process a URL stays authorised
/// once it has been resolved, so a green run here does **not** prove that
/// bookmarks survive a relaunch. Only quitting the app and launching it again
/// proves that, and that check lives in `Scripts/verify-relaunch.sh`.
final class ImportAndAccessTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TestImages.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writePhotograph(_ name: String, width: Int = 800, height: Int = 600) throws -> URL {
        let image = try TestImages.makeCGImage(width: width, height: height)
        return try TestImages.write(image, as: .jpeg, to: directory.appendingPathComponent(name))
    }

    func testMakeReferenceRecordsIdentityDimensionsAndSize() throws {
        let url = try writePhotograph("one.jpg", width: 1600, height: 900)
        let reference = try Importer.makeReference(for: url)

        XCTAssertEqual(reference.displayName, "one.jpg")
        XCTAssertEqual(reference.pixelWidth, 1600)
        XCTAssertEqual(reference.pixelHeight, 900)
        XCTAssertEqual(reference.aspectRatio, 16.0 / 9.0, accuracy: 0.01)
        XCTAssertGreaterThan(reference.fileSize, 0)
        XCTAssertFalse(reference.bookmark.isEmpty)
        XCTAssertEqual(reference.id, try ContentHasher.hash(contentsOf: url))
    }

    func testResolverReadsThroughTheBookmark() throws {
        let url = try writePhotograph("two.jpg")
        let reference = try Importer.makeReference(for: url)
        let resolver = BookmarkResolver()

        let thumbnail = try resolver.withAccess(reference) { resolved in
            try ThumbnailDecoder.decode(url: resolved, maxPixelSize: 256)
        }
        XCTAssertEqual(max(thumbnail.image.width, thumbnail.image.height), 256)
    }

    /// Files move. That is normal, and must surface as a nameable state rather
    /// than a crash or an empty grid with no explanation.
    func testMovedPhotographReportsMissingRatherThanFailingSilently() throws {
        let url = try writePhotograph("three.jpg")
        let reference = try Importer.makeReference(for: url)
        let resolver = BookmarkResolver()
        try FileManager.default.removeItem(at: url)

        XCTAssertThrowsError(try resolver.withAccess(reference) { _ in }) { error in
            guard case PhotoAccessError.missing = error else {
                return XCTFail("expected .missing, got \(error)")
            }
        }
    }

    func testExpandFindsPhotographsInsideAFolderAndIgnoresTheRest() throws {
        _ = try writePhotograph("a.jpg")
        _ = try writePhotograph("b.jpg")
        let nested = directory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let image = try TestImages.makeCGImage(width: 100, height: 100)
        try TestImages.write(image, as: .png, to: nested.appendingPathComponent("c.png"))
        try Data("notes".utf8).write(to: directory.appendingPathComponent("readme.txt"))

        let found = Importer.expand([directory])

        XCTAssertEqual(found.map(\.lastPathComponent), ["a.jpg", "b.jpg", "c.png"])
    }

    func testBulkImportDeDuplicatesByContent() async throws {
        let first = try writePhotograph("original.jpg")
        let copy = directory.appendingPathComponent("copy.jpg")
        try FileManager.default.copyItem(at: first, to: copy)

        let result = await Importer.makeReferences(for: [first, copy])
        XCTAssertEqual(result.references.count, 2)
        XCTAssertEqual(result.failures.count, 0)

        var document = LibraryDocument()
        for reference in result.references { document.insert(reference) }

        // Two paths, one photograph — which is what makes All Photos de-duplicate.
        XCTAssertEqual(document.allPhotos.count, 1)
    }

    func testBulkImportSurvivesOneBadFile() async throws {
        let good = try writePhotograph("good.jpg")
        let bad = directory.appendingPathComponent("bad.jpg")
        try Data("not an image".utf8).write(to: bad)

        let result = await Importer.makeReferences(for: [good, bad])

        XCTAssertEqual(result.references.map(\.displayName), ["good.jpg"])
        XCTAssertEqual(result.failures.count, 1)
    }
}
