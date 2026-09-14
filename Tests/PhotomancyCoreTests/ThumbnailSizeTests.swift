import XCTest
import CoreGraphics
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
        XCTAssertEqual(ThumbnailSize.bucket(forPixels: 9000), 5120)
    }

    func testNonPositiveSizesAreSafe() {
        XCTAssertEqual(ThumbnailSize.bucket(forPixels: 0), 128)
        XCTAssertEqual(ThumbnailSize.bucket(forPixels: -40), 128)
    }

    func testRetinaScaleIsApplied() {
        XCTAssertEqual(ThumbnailSize.bucket(forPoints: 160, scale: 1), 192)
        XCTAssertEqual(ThumbnailSize.bucket(forPoints: 160, scale: 2), 384)
    }

    /// Fit puts the photograph's longest edge against the cell's longest edge,
    /// whichever way round either of them is. Asking from the cell's height
    /// alone decodes every landscape frame too small.
    func testCellBucketUsesTheLongestEdge() {
        XCTAssertEqual(ThumbnailSize.bucket(forCell: CGSize(width: 256, height: 160), scale: 1), 256)
        XCTAssertEqual(ThumbnailSize.bucket(forCell: CGSize(width: 160, height: 256), scale: 1), 256)
        XCTAssertEqual(ThumbnailSize.bucket(forCell: CGSize(width: 256, height: 160), scale: 2), 512)
    }

    func testCellBucketNeverAsksForLessThanTheHeightAlone() {
        for width in stride(from: 60.0, through: 400.0, by: 20) {
            let cell = CGSize(width: width, height: 160)
            XCTAssertGreaterThanOrEqual(
                ThumbnailSize.bucket(forCell: cell, scale: 2),
                ThumbnailSize.bucket(forPoints: 160, scale: 2)
            )
        }
    }

    /// The point of the ladder: a window drag across a range of sizes must not
    /// produce a different decode at every intermediate width.
    func testNearbySizesShareABucket() {
        let buckets = Set((150...190).map { ThumbnailSize.bucket(forPoints: Double($0), scale: 2) })
        XCTAssertEqual(buckets.count, 1)
    }

    // MARK: - Decoding for one photograph

    /// A portrait frame in a landscape window is drawn at the window's height;
    /// asking from the width would decode far more than can be shown.
    func testAPortraitPhotographIsDecodedForItsOwnLongEdge() {
        let drawn = fitted(aspectRatio: 2.0 / 3.0, in: CGRect(x: 0, y: 0, width: 2400, height: 1400))
        XCTAssertEqual(ThumbnailSize.bucket(forPhotograph: drawn.size, originalLongEdge: 6000, scale: 2), 3072)
        XCTAssertEqual(ThumbnailSize.bucket(forCell: CGSize(width: 2400, height: 1400), scale: 2), 5120,
                       "what the area alone would have asked for")
    }

    /// ImageIO never enlarges, so asking for more only stores duplicates.
    func testTheRequestNeverExceedsTheOriginal() {
        XCTAssertEqual(ThumbnailSize.bucket(forPhotograph: CGSize(width: 1500, height: 1000), originalLongEdge: 1600, scale: 2), 1600)
        XCTAssertEqual(ThumbnailSize.bucket(forPhotograph: CGSize(width: 3000, height: 2000), originalLongEdge: 1600, scale: 2), 1600,
                       "a larger window asks the same key")
    }

    func testALargeOriginalStaysOnTheLadder() {
        XCTAssertEqual(ThumbnailSize.bucket(forPhotograph: CGSize(width: 1400, height: 933), originalLongEdge: 6000, scale: 2), 3072)
    }
}
