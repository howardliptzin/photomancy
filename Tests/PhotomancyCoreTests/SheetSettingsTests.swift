import XCTest
import CoreGraphics
@testable import PhotomancyCore

final class SheetSettingsTests: XCTestCase {

    func testDefaultCellShapeIsSquare() {
        XCTAssertEqual(SheetSettings().cellShape, .square)
    }

    /// The default is a starting value, not a constraint: each collection keeps
    /// its own shape, and All Photos keeps one too.
    func testEachCollectionKeepsItsOwnCellShape() {
        var document = LibraryDocument()
        let panoramas = document.addCollection(named: "Panoramas")
        let portraits = document.addCollection(named: "Portraits")

        var wide = SheetSettings()
        wide.cellShape = .threeByTwo
        document.updateSettings(wide, for: panoramas.id)

        var derived = SheetSettings()
        derived.cellShape = .derivedFromCollection
        document.updateSettings(derived, for: portraits.id)

        XCTAssertEqual(document.settings(for: panoramas.id).cellShape, .threeByTwo)
        XCTAssertEqual(document.settings(for: portraits.id).cellShape, .derivedFromCollection)
        XCTAssertEqual(document.settings(for: nil).cellShape, .square, "All Photos is untouched")
    }

    func testPerCollectionShapeSurvivesASaveAndLoad() throws {
        var document = LibraryDocument()
        let collection = document.addCollection(named: "Square shoot")
        var settings = SheetSettings()
        settings.cellShape = .fourByThree
        settings.columns = 7
        document.updateSettings(settings, for: collection.id)

        let restored = try JSONDecoder().decode(
            LibraryDocument.self, from: JSONEncoder().encode(document)
        )
        XCTAssertEqual(restored.settings(for: collection.id).cellShape, .fourByThree)
        XCTAssertEqual(restored.settings(for: collection.id).columns, 7)
    }

    /// A library written before `cellShape` existed must still open. Without
    /// defaulted decoding this throws, and LibraryStore refuses to overwrite a
    /// file it could not read — so the person sees an empty grid and an intact
    /// library, which is the worst of both.
    func testSettingsWrittenBeforeCellShapeExistedStillLoad() throws {
        let old = Data("""
        {"columns":5,"rows":4,"gap":12,"backgroundHex":"#FFFFFF","cellMode":"fit"}
        """.utf8)

        let settings = try JSONDecoder().decode(SheetSettings.self, from: old)

        XCTAssertEqual(settings.cellShape, .square)
        XCTAssertEqual(settings.columns, 5)
        XCTAssertEqual(settings.cellMode, .fit)
    }

    func testAnEmptySettingsObjectIsAllDefaults() throws {
        let settings = try JSONDecoder().decode(SheetSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings, SheetSettings())
    }

    /// Settled: the side margins on A4 landscape are accepted, not a bug to be
    /// tuned away by quietly changing the default grid.
    func testDefaultGridIsFiveByFour() {
        XCTAssertEqual(SheetSettings().columns, 5)
        XCTAssertEqual(SheetSettings().rows, 4)
    }

    // MARK: - Paper

    func testDefaultPaperIsA4Landscape() {
        XCTAssertEqual(SheetSettings().paper, Paper(size: .a4, orientation: .landscape))
        XCTAssertEqual(SheetSettings().paper.millimetres, CGSize(width: 297, height: 210))
    }

    /// This is the number `CellShape.matchPage` resolves to.
    func testPaperAspect() {
        XCTAssertEqual(Paper(size: .a4, orientation: .landscape).aspect, 297.0 / 210.0, accuracy: 0.0001)
        XCTAssertEqual(Paper(size: .a4, orientation: .portrait).aspect, 210.0 / 297.0, accuracy: 0.0001)
        XCTAssertEqual(Paper(size: .usLetter, orientation: .landscape).aspect, 11.0 / 8.5, accuracy: 0.001)
    }

    func testPointsAreSeventyTwoToTheInch() {
        let a4 = Paper(size: .a4, orientation: .portrait).points
        XCTAssertEqual(a4.width, 595.28, accuracy: 0.01)
        XCTAssertEqual(a4.height, 841.89, accuracy: 0.01)
    }

    func testOrientationOnlySwapsTheEdges() {
        let portrait = Paper(size: .a4, orientation: .portrait).millimetres
        let landscape = Paper(size: .a4, orientation: .landscape).millimetres
        XCTAssertEqual(portrait.width, landscape.height)
        XCTAssertEqual(portrait.height, landscape.width)
    }

    func testPaperIsPerCollection() {
        var document = LibraryDocument()
        let panoramas = document.addCollection(named: "Panoramas")
        var settings = SheetSettings()
        settings.paper = Paper(size: .usLetter, orientation: .portrait)
        document.updateSettings(settings, for: panoramas.id)

        XCTAssertEqual(document.settings(for: panoramas.id).paper.size, .usLetter)
        XCTAssertEqual(document.settings(for: nil).paper, Paper(), "All Photos is untouched")
    }

    func testLibraryWrittenBeforePaperExistedStillLoads() throws {
        let old = Data("""
        {"columns":5,"rows":4,"gap":12,"backgroundHex":"#FFFFFF","cellMode":"fit"}
        """.utf8)
        let settings = try JSONDecoder().decode(SheetSettings.self, from: old)
        XCTAssertEqual(settings.paper, Paper(size: .a4, orientation: .landscape))
    }
}
