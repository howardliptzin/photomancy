import XCTest
@testable import PhotomancyCore

final class ThumbnailSizeTests: XCTestCase {

    func testRoundsUpToTheLadder() {
        XCTAssertEqual(ThumbnailSize.bucket(forPixels: 1), 128)
        XCTAssertEqual(ThumbnailSize.bucket(forPixels: 128), 128)
        XCTAssertEqual(ThumbnailSize.bucket(forPixels: 129), 192)
        XCTAssertEqual(ThumbnailSize.bucket(forPixels: 500), 512)
        XCTAssertEqual(ThumbnailSize.bucket(forPixels: 513), 768)
    }

    func testClampsAboveTheLadder() {
        XCTAssertEqual(ThumbnailSize.bucket(forPixels: 9000), 2048)
    }

    func testNonPositiveSizesAreSafe() {
        XCTAssertEqual(ThumbnailSize.bucket(forPixels: 0), 128)
        XCTAssertEqual(ThumbnailSize.bucket(forPixels: -40), 128)
    }

    func testRetinaScaleIsApplied() {
        XCTAssertEqual(ThumbnailSize.bucket(forPoints: 160, scale: 1), 192)
        XCTAssertEqual(ThumbnailSize.bucket(forPoints: 160, scale: 2), 384)
    }

    /// The point of the ladder: a window drag across a range of sizes must not
    /// produce a different decode at every intermediate width.
    func testNearbySizesShareABucket() {
        let buckets = Set((150...190).map { ThumbnailSize.bucket(forPoints: Double($0), scale: 2) })
        XCTAssertEqual(buckets.count, 1)
    }
}
