import XCTest
@testable import PhotomancyCore

/// Where a drag out of the sheet lands in the sidebar.
final class SidebarDropTests: XCTestCase {

    private let sidebar = CGRect(x: 0, y: 0, width: 200, height: 600)
    private let button = CGRect(x: 0, y: 560, width: 200, height: 40)
    private let allPhotos = CGRect(x: 0, y: 20, width: 200, height: 24)
    private let vintage = UUID()
    private let beach = UUID()

    private var rows: [(id: UUID, frame: CGRect)] {
        [(vintage, CGRect(x: 0, y: 70, width: 200, height: 24)),
         (beach, CGRect(x: 0, y: 94, width: 200, height: 24))]
    }

    private func drop(at point: CGPoint, from source: UUID?) -> SidebarDrop? {
        SidebarDrop.resolve(
            point,
            sidebar: sidebar,
            newCollectionButton: button,
            allPhotosRow: allPhotos,
            collectionRows: rows,
            source: source
        )
    }

    func testOutsideTheSidebarIsStillTheSheetsBusiness() {
        XCTAssertNil(drop(at: CGPoint(x: 400, y: 80), from: vintage))
    }

    func testOnAnotherCollectionMovesThere() {
        XCTAssertEqual(drop(at: CGPoint(x: 50, y: 100), from: vintage), .collection(beach))
    }

    func testOnTheCollectionItCameFromDoesNothing() {
        XCTAssertEqual(drop(at: CGPoint(x: 50, y: 80), from: vintage), .refused)
    }

    /// All Photos holds nothing of its own, so nothing can be moved into it.
    func testOnAllPhotosDoesNothing() {
        XCTAssertEqual(drop(at: CGPoint(x: 50, y: 30), from: vintage), .refused)
    }

    /// From All Photos every collection is a destination.
    func testFromAllPhotosEveryCollectionTakesThem() {
        XCTAssertEqual(drop(at: CGPoint(x: 50, y: 80), from: nil), .collection(vintage))
    }

    func testEmptySidebarSpaceMakesANewCollection() {
        XCTAssertEqual(drop(at: CGPoint(x: 50, y: 300), from: vintage), .newCollection)
    }

    func testTheNewCollectionButtonMakesOne() {
        XCTAssertEqual(drop(at: CGPoint(x: 50, y: 580), from: vintage), .newCollection)
    }

    /// A label is narrower than its row: the whole width of the sidebar at that
    /// height is the row.
    func testARowIsItsWholeWidthNotItsLabel() {
        let result = SidebarDrop.resolve(
            CGPoint(x: 190, y: 100),
            sidebar: sidebar,
            newCollectionButton: button,
            allPhotosRow: allPhotos,
            collectionRows: [(beach, CGRect(x: 30, y: 94, width: 60, height: 16))],
            source: vintage
        )
        XCTAssertEqual(result, .collection(beach))
    }

    /// Passing between two rows must not flicker to a new collection; the
    /// nearer row takes it.
    func testBetweenTwoRowsTheNearerOneTakesIt() {
        let rows: [(id: UUID, frame: CGRect)] = [
            (vintage, CGRect(x: 0, y: 70, width: 200, height: 16)),
            (beach, CGRect(x: 0, y: 98, width: 200, height: 16)),
        ]
        func at(_ y: CGFloat) -> SidebarDrop? {
            SidebarDrop.resolve(CGPoint(x: 50, y: y), sidebar: sidebar, newCollectionButton: button,
                                allPhotosRow: allPhotos, collectionRows: rows, source: nil, slack: 8)
        }
        XCTAssertEqual(at(89), .collection(vintage))
        XCTAssertEqual(at(95), .collection(beach))
        XCTAssertEqual(at(300), .newCollection, "well below the last row is empty space")
    }

    /// A row scrolled under the button is hidden there; the button is what
    /// the person sees.
    func testTheButtonWinsOverARowScrolledBeneathIt() {
        let hidden = UUID()
        let result = SidebarDrop.resolve(
            CGPoint(x: 50, y: 570),
            sidebar: sidebar,
            newCollectionButton: button,
            allPhotosRow: allPhotos,
            collectionRows: [(hidden, CGRect(x: 0, y: 560, width: 200, height: 24))],
            source: vintage
        )
        XCTAssertEqual(result, .newCollection)
    }
}
