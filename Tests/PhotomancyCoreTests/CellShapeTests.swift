import XCTest
@testable import PhotomancyCore

final class CellShapeTests: XCTestCase {

    private func photograph(_ seed: String, width: Int, height: Int) -> PhotoReference {
        PhotoReference(
            id: ContentHasher.hash(Data(seed.utf8)),
            displayName: "\(seed).jpg",
            fileSize: 1,
            pixelWidth: width,
            pixelHeight: height,
            bookmark: Data()
        )
    }

    private func shoot(_ prefix: String, count: Int, width: Int, height: Int) -> [PhotoReference] {
        (0..<count).map { photograph("\(prefix)-\($0)", width: width, height: height) }
    }

    // MARK: - Fixed shapes

    func testFixedShapesIgnoreTheCollection() {
        let mixed = shoot("a", count: 3, width: 6000, height: 4000)
        XCTAssertEqual(CellShape.square.aspect(for: mixed), 1)
        XCTAssertEqual(CellShape.threeByTwo.aspect(for: mixed), 1.5)
        XCTAssertEqual(CellShape.fourByThree.aspect(for: mixed), 4.0 / 3.0, accuracy: 0.0001)
    }

    // MARK: - Derived

    func testAUniformCollectionDerivesItsOwnRatio() {
        let landscape = shoot("l", count: 10, width: 6000, height: 4000)
        XCTAssertEqual(CellShape.derivedFromCollection.aspect(for: landscape), 1.5, accuracy: 0.0001)
    }

    func testAMajorityIsEnough() {
        // 6 of 10 landscape 3:2 — more than half, so it wins.
        let photographs = shoot("l", count: 6, width: 6000, height: 4000)
            + shoot("p", count: 4, width: 4000, height: 6000)
        XCTAssertEqual(CellShape.derivedFromCollection.aspect(for: photographs), 1.5, accuracy: 0.0001)
    }

    /// Exactly half is not a majority. "+51%", not "the most common".
    func testAnExactHalfIsNotAMajority() {
        let photographs = shoot("l", count: 5, width: 6000, height: 4000)
            + shoot("p", count: 5, width: 4000, height: 6000)
        XCTAssertNil(CellShape.majorityAspect(of: photographs))
        XCTAssertEqual(CellShape.derivedFromCollection.aspect(for: photographs), 1)
    }

    /// The fallback lands on square exactly where square is provably right: a
    /// collection of mixed orientation, where a photograph and its transpose
    /// must occupy the same area.
    func testNoMajorityFallsBackToSquare() {
        let photographs = shoot("a", count: 4, width: 6000, height: 4000)
            + shoot("b", count: 4, width: 4000, height: 6000)
            + shoot("c", count: 3, width: 4032, height: 3024)
        XCTAssertNil(CellShape.majorityAspect(of: photographs))
        XCTAssertEqual(CellShape.derivedFromCollection.aspect(for: photographs), 1)
    }

    func testAnEmptyCollectionIsSquare() {
        XCTAssertNil(CellShape.majorityAspect(of: []))
        XCTAssertEqual(CellShape.derivedFromCollection.aspect(for: []), 1)
    }

    /// A frame that has been straightened or exported at an odd size is still a
    /// 3:2 frame. Without a tolerance one stray pixel splits the cluster and the
    /// majority is lost.
    func testNearlyIdenticalRatiosClusterTogether() {
        let photographs = shoot("exact", count: 4, width: 6000, height: 4000)
            + shoot("nudged", count: 3, width: 5988, height: 4000)
        let derived = try? XCTUnwrap(CellShape.majorityAspect(of: photographs))
        XCTAssertNotNil(derived)
        XCTAssertEqual(derived ?? 0, 1.5, accuracy: 0.01)
    }

    func testGenuinelyDifferentRatiosDoNotCluster() {
        let photographs = shoot("three-two", count: 5, width: 6000, height: 4000)
            + shoot("four-three", count: 5, width: 4032, height: 3024)
        XCTAssertNil(CellShape.majorityAspect(of: photographs))
    }

    /// The shape resolves against the collection it belongs to, not the library.
    func testDerivationIsPerCollection() {
        var document = LibraryDocument()
        let square = document.addCollection(named: "Square shoot")
        for photograph in shoot("sq", count: 4, width: 3000, height: 3000) {
            document.insert(photograph)
            document.add([photograph.id], to: square.id)
        }
        for photograph in shoot("wide", count: 9, width: 6000, height: 4000) {
            document.insert(photograph)
        }

        XCTAssertEqual(document.cellAspect(for: square.id), 1, accuracy: 0.0001)
        XCTAssertEqual(document.cellAspect(for: nil), 1.5, accuracy: 0.0001,
                       "All Photos derives from the whole library")
    }
}
