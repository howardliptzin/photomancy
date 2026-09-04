import XCTest
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
}
