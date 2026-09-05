import XCTest
@testable import PhotomancyCore

/// Pins must survive a quit. That is the part of the persistence requirement
/// marked critical: collections and pins intact on reopening.
final class PinTests: XCTestCase {

    private func reference(_ seed: String) -> PhotoReference {
        PhotoReference(
            id: ContentHasher.hash(Data(seed.utf8)),
            displayName: "\(seed).jpg",
            fileSize: 1,
            pixelWidth: 6000,
            pixelHeight: 4000,
            bookmark: Data()
        )
    }

    func testPinsAreKeptPerCollectionIncludingAllPhotos() {
        var document = LibraryDocument()
        let collection = document.addCollection(named: "Set")
        document.insert(reference("a"))

        document.updatePins([Pin(photo: reference("a").id, cell: 7)], for: collection.id)
        document.updatePins([Pin(photo: reference("a").id, cell: 2)], for: nil)

        XCTAssertEqual(document.pins(in: collection.id).first?.cell, 7)
        XCTAssertEqual(document.pins(in: nil).first?.cell, 2)
    }

    /// A pin records the cell, not just the fact of being pinned, so a pinned
    /// photograph returns to where it was left rather than being re-rolled.
    func testAPinRemembersItsCellThroughASaveAndLoad() throws {
        var document = LibraryDocument()
        let collection = document.addCollection(named: "Set")
        document.insert(reference("a"))
        document.insert(reference("b"))
        document.updatePins([
            Pin(photo: reference("a").id, cell: 3),
            Pin(photo: reference("b").id, cell: 11),
        ], for: collection.id)

        let restored = try JSONDecoder().decode(
            LibraryDocument.self, from: JSONEncoder().encode(document)
        )

        XCTAssertEqual(restored.pins(in: collection.id).map(\.cell), [3, 11])
    }

    func testRemovingAPhotographRemovesItsPinsEverywhere() {
        var document = LibraryDocument()
        let collection = document.addCollection(named: "Set")
        document.insert(reference("a"))
        document.insert(reference("b"))
        document.updatePins([Pin(photo: reference("a").id, cell: 1)], for: collection.id)
        document.updatePins([Pin(photo: reference("a").id, cell: 4)], for: nil)

        document.remove([reference("a").id])

        XCTAssertTrue(document.pins(in: collection.id).isEmpty)
        XCTAssertTrue(document.pins(in: nil).isEmpty)
    }

    // MARK: - The collection that was open

    func testTheOpenCollectionIsRememberedAcrossASaveAndLoad() throws {
        var document = LibraryDocument()
        let collection = document.addCollection(named: "Set")
        document.lastOpenedCollection = collection.id

        let restored = try JSONDecoder().decode(
            LibraryDocument.self, from: JSONEncoder().encode(document)
        )
        XCTAssertEqual(restored.lastOpenedCollection, collection.id)
    }

    /// Deleting the collection you were last in must not leave the app pointing
    /// at something that no longer exists. All Photos is always a valid answer.
    func testDeletingTheRememberedCollectionFallsBackToAllPhotos() {
        var document = LibraryDocument()
        let collection = document.addCollection(named: "Set")
        document.lastOpenedCollection = collection.id

        document.removeCollection(collection.id)

        XCTAssertNil(document.lastOpenedCollection)
    }
}
