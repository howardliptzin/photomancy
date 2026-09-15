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

    /// The union of the collections, each photograph once however many hold it.
    func testAllPhotosIsEveryReferenceOnce() {
        var document = LibraryDocument()
        document.insert(reference("a"))
        document.insert(reference("b"))
        let one = document.addCollection(named: "One")
        let two = document.addCollection(named: "Two")
        document.add([reference("a").id, reference("b").id], to: one.id)
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

    /// All Photos is not a stored collection, so its settings have nowhere else to live.
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

    /// Removing inside a collection takes the photograph out of that list, and
    /// out of the library only when no other collection holds it.
    func testRemovingFromACollectionKeepsAPhotographAnotherCollectionHolds() {
        var document = LibraryDocument()
        document.insert(reference("a"))
        document.insert(reference("b"))
        let collection = document.addCollection(named: "Set")
        let other = document.addCollection(named: "Other")
        document.add([reference("a").id, reference("b").id], to: collection.id)
        document.add([reference("a").id], to: other.id)

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

    // MARK: - All Photos is the union of the collections

    /// Deleting a collection takes what only it held; what another collection
    /// holds stays.
    func testDeletingACollectionRemovesOnlyThePhotographsNoOtherHolds() {
        var document = LibraryDocument()
        for seed in ["a", "b", "c"] { document.insert(reference(seed)) }
        let doomed = document.addCollection(named: "Doomed")
        let kept = document.addCollection(named: "Kept")
        document.add([reference("a").id, reference("b").id], to: doomed.id)
        document.add([reference("b").id, reference("c").id], to: kept.id)
        document.updatePins([Pin(photo: reference("a").id, cell: 1), Pin(photo: reference("b").id, cell: 2)], for: nil)

        let departed = document.removeCollection(doomed.id)

        XCTAssertEqual(departed, [reference("a").id])
        XCTAssertEqual(Set(document.allPhotos.map(\.displayName)), ["b.jpg", "c.jpg"])
        XCTAssertEqual(document.pins(in: nil).map(\.photo), [reference("b").id])
    }

    func testAddingToACollectionThatDoesNotExistAddsNothing() {
        var document = LibraryDocument()
        document.insert(reference("a"))
        document.add([reference("a").id], to: UUID())
        XCTAssertTrue(document.collections.isEmpty)
    }

    /// The one public way in. Nothing enters the library without a collection to
    /// go into, and a photograph already there still joins a second collection.
    func testPhotographsEnterTheLibraryOnlyIntoACollection() {
        var document = LibraryDocument()
        XCTAssertEqual(document.add([reference("a")], to: UUID()), 0)
        XCTAssertTrue(document.references.isEmpty, "no collection, nothing added")

        let one = document.addCollection(named: "One")
        let two = document.addCollection(named: "Two")
        XCTAssertEqual(document.add([reference("a")], to: one.id), 1)
        XCTAssertEqual(document.add([reference("a")], to: two.id), 0, "already in the library")
        XCTAssertEqual(document.photos(in: two.id).map(\.displayName), ["a.jpg"])
    }
}
