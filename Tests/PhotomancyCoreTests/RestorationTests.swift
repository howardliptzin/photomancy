import XCTest
@testable import PhotomancyCore

/// Removing from a collection has to be exactly reversible, because it is the
/// one deletion that offers undo. Deleting from the library does not, by
/// decision, so nothing here covers it.
final class RestorationTests: XCTestCase {

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

    private func library(_ names: [String]) -> (LibraryDocument, UUID) {
        var document = LibraryDocument()
        for name in names { document.insert(reference(name)) }
        let collection = document.addCollection(named: "Set")
        document.add(names.map { reference($0).id }, to: collection.id)
        return (document, collection.id)
    }

    func testRemovingReportsWhereEachPhotographSat() throws {
        var (document, collection) = library(["a", "b", "c", "d"])

        let restoration = try XCTUnwrap(
            document.removeFromCollection([reference("b").id, reference("d").id], collectionID: collection)
        )

        XCTAssertEqual(restoration.memberships.map(\.index), [1, 3])
        XCTAssertEqual(restoration.memberships.map(\.photo), [reference("b").id, reference("d").id])
        XCTAssertEqual(document.photos(in: collection).map(\.displayName), ["a.jpg", "c.jpg"])
    }

    /// The reference itself is untouched — that is what makes this the cheap,
    /// reversible deletion.
    func testTheReferenceStaysInTheLibrary() throws {
        var (document, collection) = library(["a", "b"])
        _ = document.removeFromCollection([reference("a").id], collectionID: collection)
        XCTAssertEqual(document.allPhotos.count, 2)
    }

    /// Membership is ordered, so putting it back at the end would be a different
    /// collection from the one that was there.
    func testUndoRestoresTheExactOrder() throws {
        var (document, collection) = library(["a", "b", "c", "d", "e"])
        let before = document.photos(in: collection).map(\.displayName)

        let restoration = try XCTUnwrap(
            document.removeFromCollection([reference("b").id, reference("d").id], collectionID: collection)
        )
        document.restore(restoration)

        XCTAssertEqual(document.photos(in: collection).map(\.displayName), before)
    }

    func testUndoRestoresAPhotographRemovedFromTheFront() throws {
        var (document, collection) = library(["a", "b", "c"])
        let restoration = try XCTUnwrap(
            document.removeFromCollection([reference("a").id], collectionID: collection)
        )
        document.restore(restoration)
        XCTAssertEqual(document.photos(in: collection).map(\.displayName), ["a.jpg", "b.jpg", "c.jpg"])
    }

    func testPinsGoWithThePhotographAndComeBackWithIt() throws {
        var (document, collection) = library(["a", "b", "c"])
        document.updatePins([
            Pin(photo: reference("b").id, cell: 4),
            Pin(photo: reference("c").id, cell: 9),
        ], for: collection)

        let restoration = try XCTUnwrap(
            document.removeFromCollection([reference("b").id], collectionID: collection)
        )
        XCTAssertEqual(restoration.pins, [Pin(photo: reference("b").id, cell: 4)])
        XCTAssertEqual(document.pins(in: collection).map(\.photo), [reference("c").id])

        document.restore(restoration)
        XCTAssertEqual(Set(document.pins(in: collection)), [
            Pin(photo: reference("b").id, cell: 4),
            Pin(photo: reference("c").id, cell: 9),
        ])
    }

    func testRestoringTwiceDoesNotDuplicate() throws {
        var (document, collection) = library(["a", "b"])
        let restoration = try XCTUnwrap(
            document.removeFromCollection([reference("a").id], collectionID: collection)
        )
        document.restore(restoration)
        document.restore(restoration)
        XCTAssertEqual(document.photos(in: collection).map(\.displayName), ["a.jpg", "b.jpg"])
    }

    /// A no-op must not land in the history as a step that appears to do
    /// something and then undoes nothing.
    func testRemovingSomethingAbsentReportsNothingToUndo() {
        var (document, collection) = library(["a"])
        XCTAssertNil(document.removeFromCollection([reference("zz").id], collectionID: collection))
        XCTAssertNil(document.removeFromCollection([reference("a").id], collectionID: UUID()))
    }

    // MARK: - The sheet

    /// The gap closes: everything after the removal shuffles up one place,
    /// rather than the sheet re-dealing or a hole being left behind.
    func testRemovingClosesTheGap() {
        let photographs = ["a", "b", "c", "d"].map(reference)
        var arrangement = Arrangement(slots: photographs.map { $0.id }, pins: [])

        arrangement.removeClosingGaps([photographs[1].id])

        XCTAssertEqual(arrangement.slots, [photographs[0].id, photographs[2].id, photographs[3].id, nil])
    }

    /// A pin holds a photograph across rolls, not at a fixed cell for ever — so
    /// when the sheet closes up, the pin travels with its photograph instead of
    /// being stranded on the cell it used to occupy.
    func testAPinTravelsWithItsPhotographWhenTheSheetClosesUp() {
        let photographs = ["a", "b", "c"].map(reference)
        var arrangement = Arrangement(slots: photographs.map { $0.id }, pins: [])
        arrangement.togglePin(at: 2)
        XCTAssertEqual(arrangement.pins.first?.cell, 2)

        arrangement.removeClosingGaps([photographs[0].id])

        XCTAssertEqual(arrangement.photograph(at: 1), photographs[2].id)
        XCTAssertEqual(arrangement.pins.first?.cell, 1, "the pin moved with it")
        XCTAssertTrue(arrangement.isPinned(cell: 1))
    }

    func testRemovingDropsThePinOnWhatWasRemoved() {
        let photographs = ["a", "b"].map(reference)
        var arrangement = Arrangement(slots: photographs.map { $0.id }, pins: [])
        arrangement.togglePin(at: 1)

        arrangement.removeClosingGaps([photographs[1].id])
        XCTAssertTrue(arrangement.pins.isEmpty)
    }

    func testRemovingSeveralAtOnceClosesEveryGap() {
        let photographs = ["a", "b", "c", "d", "e"].map(reference)
        var arrangement = Arrangement(slots: photographs.map { $0.id }, pins: [])

        arrangement.removeClosingGaps([photographs[0].id, photographs[3].id])

        XCTAssertEqual(arrangement.slots, [photographs[1].id, photographs[2].id, photographs[4].id, nil, nil])
    }

    /// A pin held over from a larger grid refers to no cell on this sheet, and
    /// must not be rewritten by a removal it has nothing to do with.
    func testAPinForAPhotographNotOnTheSheetIsLeftAlone() {
        let photographs = ["a", "b"].map(reference)
        let elsewhere = Pin(photo: reference("z").id, cell: 40)
        var arrangement = Arrangement(slots: photographs.map { $0.id }, pins: [elsewhere])

        arrangement.removeClosingGaps([photographs[0].id])

        XCTAssertEqual(arrangement.pins, [elsewhere])
    }
}
