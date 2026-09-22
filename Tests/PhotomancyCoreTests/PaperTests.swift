import XCTest
import CoreGraphics
@testable import PhotomancyCore

/// Any paper the print panel offers, remembered — without the one-way door
/// that adding a case to `Paper.Size` would have been.
final class PaperTests: XCTestCase {

    private let a3 = CGSize(width: 1190.55, height: 841.89)   // A3 landscape, points
    private let thirteenByNineteen = CGSize(width: 936, height: 1368)

    private func roundTrip(_ paper: Paper) throws -> Paper {
        let data = try JSONEncoder().encode(paper)
        return try JSONDecoder().decode(Paper.self, from: data)
    }

    private func json(_ paper: Paper) throws -> [String: Any] {
        let data = try JSONEncoder().encode(paper)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Any paper at all

    func testAnyPaperSizeIsRemembered() throws {
        for size in [a3, thirteenByNineteen, CGSize(width: 500, height: 500)] {
            let paper = try roundTrip(Paper(points: size, name: "custom"))
            XCTAssertEqual(paper.points.width, size.width, accuracy: 0.01, "\(size)")
            XCTAssertEqual(paper.points.height, size.height, accuracy: 0.01)
            XCTAssertEqual(paper.paperName, "custom")
        }
    }

    func testOrientationFollowsTheShapeOfThePaperChosen() {
        XCTAssertEqual(Paper(points: a3).orientation, .landscape)
        XCTAssertEqual(Paper(points: thirteenByNineteen).orientation, .portrait)
    }

    func testMillimetresAreReportedForPaperTheFrozenSizesDoNotCover() {
        let millimetres = Paper(points: a3).millimetres
        XCTAssertEqual(millimetres.width, 420, accuracy: 0.5, "A3 landscape is 420 × 297 mm")
        XCTAssertEqual(millimetres.height, 297, accuracy: 0.5)
    }

    func testPaperWithNoUsableSizeFallsBackToTheDefaultRatherThanToNonsense() {
        for size in [CGSize.zero, CGSize(width: -10, height: 100), CGSize(width: CGFloat.nan, height: 100)] {
            let paper = Paper(points: size)
            XCTAssertEqual(paper.points, Paper().points, "\(size)")
        }
    }

    // MARK: - The one-way door, held shut

    /// The whole reason `Size` is frozen. If it gained a case, a build that
    /// predates the case would throw decoding it, `LibraryStore.load()` would
    /// refuse the file, and the person would open a reverted build to an empty
    /// grid over an intact library.
    func testTheFrozenSizesAreStillOnlyTheTwoThatShipped() {
        XCTAssertEqual(Paper.Size.allCases.map(\.rawValue), ["a4", "usLetter"],
                       "adding a case here breaks every older build's decoder")
    }

    /// Every save writes the legacy keys, whatever paper was chosen.
    func testTheLegacyKeysAreAlwaysWrittenEvenForPaperTheyCannotDescribe() throws {
        let written = try json(Paper(points: a3, name: "iso-a3"))
        XCTAssertNotNil(written["size"], "a build that knows nothing of pointWidth still finds this")
        XCTAssertNotNil(written["orientation"])
        XCTAssertEqual(written["pointWidth"] as? Double ?? 0, 1190.55, accuracy: 0.01)
        XCTAssertEqual(written["paperName"] as? String, "iso-a3")
    }

    /// The nearest of the two shapes, so a reverted build prints on something
    /// close rather than on nothing.
    func testTheLegacySizeWrittenIsTheNearestFrozenShape() {
        XCTAssertEqual(Paper(points: a3).size, .a4, "A3 is an A-series shape")
        XCTAssertEqual(Paper(points: CGSize(width: 612, height: 792)).size, .usLetter)
        XCTAssertEqual(Paper(points: CGSize(width: 595, height: 842)).size, .a4)
    }

    /// The other half of the same door: a library written by *this* build is
    /// read by the build before it. Simulated by decoding with only the keys
    /// the old build knew.
    func testABuildThatPredatesTheNewKeysStillReadsThisLibrary() throws {
        let written = try json(Paper(points: a3, name: "iso-a3"))
        let asOldBuildSeesIt = written.filter { ["size", "orientation"].contains($0.key) }
        let data = try JSONSerialization.data(withJSONObject: asOldBuildSeesIt)

        let paper = try JSONDecoder().decode(Paper.self, from: data)
        XCTAssertEqual(paper.size, .a4)
        XCTAssertEqual(paper.orientation, .landscape)
        XCTAssertNil(paper.pointSize, "no new keys, so nothing to be authoritative")
        XCTAssertEqual(paper.points.width, 841.89, accuracy: 0.1, "it prints A4 landscape, and it loads")
    }

    func testALibraryWrittenBeforeAnyPaperKeysExistedStillLoads() throws {
        let data = try XCTUnwrap("{}".data(using: .utf8))
        XCTAssertEqual(try JSONDecoder().decode(Paper.self, from: data), Paper(),
                       "every key falls back to its default")
    }

    func testAHalfWrittenSizeIsIgnoredRatherThanTrusted() throws {
        let data = try XCTUnwrap(#"{"size":"a4","orientation":"portrait","pointWidth":1190.55}"#.data(using: .utf8))
        let paper = try JSONDecoder().decode(Paper.self, from: data)
        XCTAssertNil(paper.pointSize, "a width with no height is not a paper size")
        XCTAssertEqual(paper.points.height, 841.89, accuracy: 0.1, "falls back to A4 portrait")
    }

    // MARK: - Still true of the two that shipped

    func testTheFrozenSizesAreUnchanged() {
        XCTAssertEqual(Paper(size: .a4, orientation: .landscape).millimetres.width, 297, accuracy: 0.01)
        XCTAssertEqual(Paper(size: .a4, orientation: .landscape).millimetres.height, 210, accuracy: 0.01)
        XCTAssertEqual(Paper(size: .usLetter, orientation: .portrait).points.width, 612, accuracy: 0.5)
        XCTAssertEqual(Paper(), Paper(size: .a4, orientation: .landscape), "A4 landscape is the default")
    }

    func testAPaperBuiltFromItsOwnPointsIsTheSamePaper() {
        for size in Paper.Size.allCases {
            for orientation in Paper.Orientation.allCases {
                let named = Paper(size: size, orientation: orientation)
                let fromPoints = Paper(points: named.points)
                XCTAssertEqual(fromPoints.size, size, "\(size) \(orientation)")
                XCTAssertEqual(fromPoints.orientation, orientation)
                XCTAssertEqual(fromPoints.points.width, named.points.width, accuracy: 0.01)
            }
        }
    }

    func testPaperSurvivesTheWholeSettingsRoundTrip() throws {
        var settings = SheetSettings()
        settings.paper = Paper(points: thirteenByNineteen, name: "custom-13x19")
        let decoded = try JSONDecoder().decode(
            SheetSettings.self, from: try JSONEncoder().encode(settings)
        )
        XCTAssertEqual(decoded.paper, settings.paper)
        XCTAssertEqual(decoded.paper.paperName, "custom-13x19")
    }
}
