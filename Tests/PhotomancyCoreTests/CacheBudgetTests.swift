import XCTest
import CoreGraphics
@testable import PhotomancyCore

/// The memory cache is sized from the window, and the arithmetic that does it
/// is the whole of the feature.
final class CacheBudgetTests: XCTestCase {

    private func megabytes(_ size: CGSize, scale: Double = 2) -> Double {
        Double(CacheBudget.memoryLimit(forSheet: size, scale: scale)) / 1024 / 1024
    }

    /// The figure the contract quotes: a 5K window wants something in the
    /// region of a couple of hundred megabytes, not the 256 MB constant that
    /// happened to be near it.
    func testAFiveKWindowLandsWhereTheContractSaysItShould() {
        // 5120 × 2880 pixels, which at 2× is 2560 × 1440 points.
        let limit = megabytes(CGSize(width: 2560, height: 1440))
        XCTAssertGreaterThan(limit, 130)
        XCTAssertLessThan(limit, 270)
    }

    /// And the case the constant got badly wrong: a small window held seven
    /// times more than it could ever use.
    func testASmallWindowAsksForFarLessThanTheOldConstant() {
        let limit = megabytes(CGSize(width: 1280, height: 800))
        XCTAssertLessThan(limit, 256, "the old fixed limit")
        XCTAssertGreaterThanOrEqual(limit, Double(CacheBudget.minimumBytes) / 1024 / 1024)
    }

    /// Area, not edge: the whole claim of the derivation. Checked on the
    /// derivation itself, because the floor and the step exist precisely to
    /// stop the public answer tracking the window exactly.
    func testTheLimitFollowsAreaRatherThanEdgeLength() throws {
        let single = try XCTUnwrap(CacheBudget.derivedBytes(forSheet: CGSize(width: 2000, height: 1200), scale: 2))
        let doubled = try XCTUnwrap(CacheBudget.derivedBytes(forSheet: CGSize(width: 4000, height: 2400), scale: 2))
        XCTAssertEqual(doubled, single * 4, accuracy: single * 1e-9,
                       "twice each edge is four times the area")
    }

    /// Points are not pixels. Forgetting this is exactly the mistake the
    /// function exists to avoid, so it is asserted rather than assumed.
    func testARetinaWindowIsFourTimesTheCacheOfTheSameSizeInPoints() throws {
        let onex = try XCTUnwrap(CacheBudget.derivedBytes(forSheet: CGSize(width: 3000, height: 2000), scale: 1))
        let twox = try XCTUnwrap(CacheBudget.derivedBytes(forSheet: CGSize(width: 3000, height: 2000), scale: 2))
        XCTAssertEqual(twox, onex * 4, accuracy: onex * 1e-9)
    }

    func testNothingIsDerivedFromASizeOrScaleThatIsNotOne() {
        XCTAssertNil(CacheBudget.derivedBytes(forSheet: .zero, scale: 2))
        XCTAssertNil(CacheBudget.derivedBytes(forSheet: CGSize(width: CGFloat.nan, height: 800), scale: 2))
        XCTAssertNil(CacheBudget.derivedBytes(forSheet: CGSize(width: 1000, height: 800), scale: 0))
    }

    func testAWindowWithNoSizeYetGetsTheFloorRatherThanNothing() {
        for size in [CGSize.zero, CGSize(width: 1200, height: 0), CGSize(width: CGFloat.nan, height: 800)] {
            XCTAssertEqual(CacheBudget.memoryLimit(forSheet: size, scale: 2), CacheBudget.minimumBytes, "\(size)")
        }
        XCTAssertEqual(CacheBudget.memoryLimit(forSheet: CGSize(width: 1000, height: 800), scale: 0),
                       CacheBudget.minimumBytes, "a scale below 1 is not a scale")
    }

    /// Not a floor on correctness — the arithmetic is right at any size — but on
    /// thrashing: re-decoding on every roll costs more than the memory saved.
    func testATinyWindowStillGetsACacheWorthHaving() {
        XCTAssertEqual(CacheBudget.memoryLimit(forSheet: CGSize(width: 400, height: 300), scale: 2),
                       CacheBudget.minimumBytes)
    }

    func testAnAbsurdWindowIsBoundedRatherThanBelieved() {
        XCTAssertEqual(CacheBudget.memoryLimit(forSheet: CGSize(width: 200_000, height: 200_000), scale: 2),
                       CacheBudget.maximumBytes)
    }

    /// The derivation, stated as arithmetic so that changing one term without
    /// changing the reasoning fails here.
    func testTheLimitIsThirteenBytesPerWindowPixel() throws {
        let size = CGSize(width: 2560, height: 1440)
        let pixels = 2560.0 * 1440 * 4     // 2× on both edges
        let expected = pixels * (CacheBudget.bytesPerPixel * CacheBudget.bucketHeadroom
                                 + CacheBudget.bytesPerPixel * CacheBudget.lightboxImages)
        XCTAssertEqual(expected / pixels, 13, accuracy: 0.001, "four bytes, 2.25 of bucket, one lightbox")
        XCTAssertEqual(try XCTUnwrap(CacheBudget.derivedBytes(forSheet: size, scale: 2)), expected, accuracy: 1)
        // Rounded up onto the step, so within one step of the derivation.
        let actual = Double(CacheBudget.memoryLimit(forSheet: size, scale: 2))
        XCTAssertGreaterThanOrEqual(actual, expected)
        XCTAssertLessThan(actual - expected, Double(CacheBudget.step))
    }

    /// A limit that followed every pixel of a window drag would re-set the
    /// cache hundreds of times and log a line for each.
    func testTheLimitDoesNotMoveForEveryPixelOfAWindowDrag() {
        var seen = Set<Int>()
        for width in stride(from: 2000.0, through: 2200.0, by: 1) {
            seen.insert(CacheBudget.memoryLimit(forSheet: CGSize(width: width, height: 1400), scale: 2))
        }
        XCTAssertLessThanOrEqual(seen.count, 4, "200 px of drag should cross very few steps, saw \(seen.sorted())")
    }

    func testEveryLimitIsAWholeNumberOfSteps() {
        for width in [1400.0, 1800, 2200, 2600, 3000] {
            let limit = CacheBudget.memoryLimit(forSheet: CGSize(width: width, height: 1400), scale: 2)
            XCTAssertEqual(limit % CacheBudget.step, 0, "\(width) gave \(limit)")
        }
    }

    func testTheCacheTakesTheLimitItIsGiven() throws {
        let directory = try TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ThumbnailCache(resolver: BookmarkResolver(), directory: directory)

        XCTAssertEqual(cache.memoryLimit, CacheBudget.minimumBytes, "starts at the floor, before any window")
        cache.setMemoryLimit(CacheBudget.memoryLimit(forSheet: CGSize(width: 2560, height: 1440), scale: 2))
        XCTAssertGreaterThan(cache.memoryLimit, CacheBudget.minimumBytes)
    }
}
