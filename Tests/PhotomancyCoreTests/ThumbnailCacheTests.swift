import XCTest
import UniformTypeIdentifiers
@testable import PhotomancyCore

final class ThumbnailCacheTests: XCTestCase {

    private var directory: URL!
    private var cacheDirectory: URL!

    override func setUpWithError() throws {
        directory = try TestImages.temporaryDirectory()
        cacheDirectory = directory.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeReference() throws -> PhotoReference {
        let image = try TestImages.makeCGImage(width: 2400, height: 1600)
        let url = try TestImages.write(image, as: .jpeg, to: directory.appendingPathComponent("p.jpg"))
        return try Importer.makeReference(for: url)
    }

    func testTiersAreUsedInOrder() async throws {
        let reference = try makeReference()
        let resolver = BookmarkResolver()
        let cache = ThumbnailCache(resolver: resolver, directory: cacheDirectory)

        _ = try await cache.thumbnail(for: reference, maxPixel: 384)
        XCTAssertEqual(cache.statistics.decodes, 1)
        XCTAssertEqual(cache.statistics.diskHits, 0)

        // Second ask: memory.
        _ = try await cache.thumbnail(for: reference, maxPixel: 384)
        XCTAssertEqual(cache.statistics.memoryHits, 1)
        XCTAssertEqual(cache.statistics.decodes, 1)

        // Memory gone, disk still there — a cold launch, warm cache.
        cache.clearMemory()
        _ = try await cache.thumbnail(for: reference, maxPixel: 384)
        XCTAssertEqual(cache.statistics.diskHits, 1)
        XCTAssertEqual(cache.statistics.decodes, 1)

        // Both gone: back to the original, through the bookmark.
        cache.clearMemory()
        try cache.clearDisk()
        _ = try await cache.thumbnail(for: reference, maxPixel: 384)
        XCTAssertEqual(cache.statistics.decodes, 2)
    }

    func testRequestedSizeIsBucketed() async throws {
        let reference = try makeReference()
        let cache = ThumbnailCache(resolver: BookmarkResolver(), directory: cacheDirectory)

        let first = try await cache.thumbnail(for: reference, maxPixel: 300)
        let second = try await cache.thumbnail(for: reference, maxPixel: 340)

        XCTAssertEqual(first.requestedMaxPixel, 384)
        XCTAssertEqual(second.requestedMaxPixel, 384)
        XCTAssertEqual(cache.statistics.decodes, 1, "sizes in the same bucket must not decode twice")
    }

    /// Twenty cells asking for the same photograph at once is one decode, not
    /// twenty. The grid does exactly this.
    func testConcurrentRequestsCoalesce() async throws {
        let reference = try makeReference()
        let cache = ThumbnailCache(resolver: BookmarkResolver(), directory: cacheDirectory)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { _ = try? await cache.thumbnail(for: reference, maxPixel: 512) }
            }
        }
        XCTAssertEqual(cache.statistics.decodes + cache.statistics.diskHits, 1)
    }

    func testMissingOriginalIsReportedNotCached() async throws {
        let reference = try makeReference()
        let cache = ThumbnailCache(resolver: BookmarkResolver(), directory: cacheDirectory)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("p.jpg"))

        do {
            _ = try await cache.thumbnail(for: reference, maxPixel: 256)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(cache.statistics.failures, 1)
        }
    }
}
