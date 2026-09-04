import XCTest
@testable import PhotomancyCore

final class DiskThumbnailCacheTests: XCTestCase {

    private var directory: URL!
    private var cache: DiskThumbnailCache!

    override func setUpWithError() throws {
        directory = try TestImages.temporaryDirectory()
        cache = DiskThumbnailCache(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testFilenameIsKeyedByContentAndSize() {
        let hash = ContentHasher.hash(Data("photo".utf8))
        XCTAssertEqual(
            DiskThumbnailCache.filename(for: hash, pixels: 512, alpha: false),
            "\(hash.hex)@512.jpg"
        )
        XCTAssertNotEqual(
            DiskThumbnailCache.filename(for: hash, pixels: 512, alpha: false),
            DiskThumbnailCache.filename(for: hash, pixels: 1024, alpha: false)
        )
    }

    func testRoundTrip() throws {
        let hash = ContentHasher.hash(Data("photo".utf8))
        let image = try TestImages.makeCGImage(width: 400, height: 300)
        cache.store(Thumbnail(image: image, requestedMaxPixel: 400), id: hash, pixels: 400)

        let loaded = try XCTUnwrap(cache.load(id: hash, pixels: 400))
        XCTAssertEqual(loaded.image.width, 400)
        XCTAssertEqual(loaded.image.height, 300)
    }

    func testMissIsNotAnError() {
        XCTAssertNil(cache.load(id: ContentHasher.hash(Data("absent".utf8)), pixels: 512))
    }

    /// A PNG with transparency must not come back flattened onto black.
    func testAlphaSurvivesTheRoundTrip() throws {
        let hash = ContentHasher.hash(Data("transparent".utf8))
        let image = try TestImages.makeCGImage(width: 200, height: 200, alpha: true)
        XCTAssertTrue(DiskThumbnailCache.hasAlpha(image))

        cache.store(Thumbnail(image: image, requestedMaxPixel: 200), id: hash, pixels: 200)
        let loaded = try XCTUnwrap(cache.load(id: hash, pixels: 200))
        XCTAssertTrue(DiskThumbnailCache.hasAlpha(loaded.image))
    }

    func testRemoveAllEmptiesTheDirectory() throws {
        let hash = ContentHasher.hash(Data("photo".utf8))
        let image = try TestImages.makeCGImage(width: 100, height: 100)
        cache.store(Thumbnail(image: image, requestedMaxPixel: 100), id: hash, pixels: 100)
        XCTAssertEqual(cache.entryCount(), 1)

        try cache.removeAll()
        XCTAssertEqual(cache.entryCount(), 0)
    }
}
