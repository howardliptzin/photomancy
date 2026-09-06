import XCTest
@testable import PhotomancyCore

final class LibraryDocumentTests: XCTestCase {

    private func reference(_ seed: String, name: String? = nil) -> PhotoReference {
        PhotoReference(
            id: ContentHasher.hash(Data(seed.utf8)),
            displayName: name ?? "\(seed).jpg",
            fileSize: 1234,
            pixelWidth: 6000,
            pixelHeight: 4000,
            bookmark: Data(seed.utf8)
        )
    }

    func testInsertIsIdempotentByContentHash() {
        var document = LibraryDocument()
        XCTAssertTrue(document.insert(reference("a")))
        // Same bytes arriving under a different filename is one photograph.
        XCTAssertFalse(document.insert(reference("a", name: "a-copy.jpg")))
        XCTAssertEqual(document.references.count, 1)
    }

    func testAllPhotosIsEveryReferenceOnce() {
        var document = LibraryDocument()
        document.insert(reference("a"))
        document.insert(reference("b"))
        let one = document.addCollection(named: "One")
        let two = document.addCollection(named: "Two")
        document.add([reference("a").id], to: one.id)
        document.add([reference("a").id], to: two.id)

        XCTAssertEqual(document.allPhotos.count, 2)
        XCTAssertEqual(document.photos(in: nil).count, 2)
    }

    func testCollectionMembershipIsOrderedAndUnique() {
        var document = LibraryDocument()
        document.insert(reference("a"))
        document.insert(reference("b"))
        let collection = document.addCollection(named: "Set")
        document.add([reference("b").id, reference("a").id, reference("b").id], to: collection.id)

        let names = document.photos(in: collection.id).map(\.displayName)
        XCTAssertEqual(names, ["b.jpg", "a.jpg"])
    }

    func testCollectionOnlyReturnsPhotographsStillInTheLibrary() {
        var document = LibraryDocument()
        document.insert(reference("a"))
        let collection = document.addCollection(named: "Set")
        document.add([reference("a").id, reference("ghost").id], to: collection.id)

        XCTAssertEqual(document.photos(in: collection.id).count, 1)
    }

    func testRemovingAReferenceRemovesItFromEveryCollection() {
        var document = LibraryDocument()
        document.insert(reference("a"))
        document.insert(reference("b"))
        let collection = document.addCollection(named: "Set")
        document.add([reference("a").id, reference("b").id], to: collection.id)

        document.remove([reference("a").id])

        XCTAssertEqual(document.references.count, 1)
        XCTAssertEqual(document.photos(in: collection.id).map(\.displayName), ["b.jpg"])
    }

    func testUpdateBookmarkReplacesTheToken() {
        var document = LibraryDocument()
        document.insert(reference("a"))
        document.updateBookmark(for: reference("a").id, to: Data("fresh".utf8))
        XCTAssertEqual(document.reference(for: reference("a").id)?.bookmark, Data("fresh".utf8))
    }

    /// All Photos is virtual, so its settings have nowhere else to live.
    func testAllPhotosCarriesItsOwnSettings() {
        var document = LibraryDocument()
        let collection = document.addCollection(named: "Set")
        var settings = SheetSettings()
        settings.columns = 9
        document.updateSettings(settings, for: nil)

        XCTAssertEqual(document.settings(for: nil).columns, 9)
        XCTAssertEqual(document.settings(for: collection.id).columns, SheetSettings().columns)
    }

    func testRoundTripsThroughJSON() throws {
        var document = LibraryDocument()
        document.insert(reference("a"))
        document.insert(reference("b"))
        let collection = document.addCollection(named: "Set")
        document.add([reference("b").id], to: collection.id)

        let data = try JSONEncoder().encode(document)
        let restored = try JSONDecoder().decode(LibraryDocument.self, from: data)

        XCTAssertEqual(restored, document)
        XCTAssertEqual(restored.references.first?.bookmark, document.references.first?.bookmark)
    }
}

extension LibraryDocumentTests {

    /// Removing inside a collection takes the photograph out of that list only.
    /// Removing in All Photos takes it out of the library. Same gesture, and the
    /// difference is which view you are standing in.
    func testRemovingFromACollectionKeepsThePhotographInTheLibrary() {
        var document = LibraryDocument()
        document.insert(reference("a"))
        document.insert(reference("b"))
        let collection = document.addCollection(named: "Set")
        document.add([reference("a").id, reference("b").id], to: collection.id)

        document.remove([reference("a").id], from: collection.id)

        XCTAssertEqual(document.photos(in: collection.id).map(\.displayName), ["b.jpg"])
        XCTAssertEqual(document.allPhotos.count, 2, "still in the library")
    }

    func testRemovingFromAllPhotosRemovesItEverywhere() {
        var document = LibraryDocument()
        document.insert(reference("a"))
        document.insert(reference("b"))
        let collection = document.addCollection(named: "Set")
        document.add([reference("a").id, reference("b").id], to: collection.id)

        document.remove([reference("a").id], from: nil)

        XCTAssertEqual(document.allPhotos.count, 1)
        XCTAssertEqual(document.photos(in: collection.id).map(\.displayName), ["b.jpg"])
    }

    func testRemovingFromAnUnknownCollectionChangesNothing() {
        var document = LibraryDocument()
        document.insert(reference("a"))
        document.remove([reference("a").id], from: UUID())
        XCTAssertEqual(document.allPhotos.count, 1)
    }
}
