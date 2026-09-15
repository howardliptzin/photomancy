import XCTest
@testable import PhotomancyCore

/// Moving photographs from one sheet to another collection. One change inside
/// the document, so All Photos — the union of the collections — never loses a
/// photograph on the way, and exactly reversible, because it is undoable.
final class MoveTests: XCTestCase {

    private func reference(_ seed: String) -> PhotoReference {
        PhotoReference(
            id: ContentHasher.hash(Data(seed.utf8)),
            displayName: "\(seed).jpg",
            fileSize: 1,
            pixelWidth: 6000,
            pixelHeight: 4000,
            bookmark: Data(seed.utf8)
        )
    }

    private func id(_ seed: String) -> ContentHash { reference(seed).id }

    private func names(_ document: LibraryDocument, _ collection: UUID?) -> [String] {
        document.photos(in: collection).map { String($0.displayName.dropLast(4)) }
    }

    /// A source collection holding `names`, and an empty destination.
    private func library(_ names: [String]) -> (LibraryDocument, source: UUID, destination: UUID) {
        var document = LibraryDocument()
        let source = document.addCollection(named: "Source")
        document.add(names.map(reference), to: source.id)
        let destination = document.addCollection(named: "Destination")
        return (document, source.id, destination.id)
    }

    // MARK: - Moving

    func testMovedPhotographsLeaveTheSourceAndJoinTheDestinationInSheetOrder() throws {
        var (document, source, destination) = library(["a", "b", "c", "d"])

        let transfer = try XCTUnwrap(document.move([id("d"), id("b")], pinned: [], from: source, to: destination))

        XCTAssertEqual(names(document, source), ["a", "c"])
        XCTAssertEqual(names(document, destination), ["d", "b"])
        XCTAssertEqual(transfer.joined, [id("d"), id("b")])
        XCTAssertEqual(transfer.removal?.memberships.map(\.index), [1, 3])
    }

    /// The reason a move is one mutation: a photograph whose only collection is
    /// the source must not pass through a moment outside the library, and must
    /// not lose its All Photos pin.
    func testAPhotographInOnlyTheSourceNeverLeavesTheLibrary() throws {
        var (document, source, destination) = library(["a", "b"])
        document.updatePins([Pin(photo: id("a"), cell: 3)], for: nil)

        let transfer = try XCTUnwrap(document.move([id("a")], pinned: [], from: source, to: destination))

        XCTAssertEqual(names(document, nil), ["a", "b"], "the library is unchanged, in order")
        XCTAssertEqual(document.pins(in: nil), [Pin(photo: id("a"), cell: 3)])
        XCTAssertEqual(transfer.removal?.departures, [])
    }

    func testPinnedPhotographsFillTheDestinationsFirstCellsInOrder() throws {
        var (document, source, destination) = library(["a", "b", "c", "d"])

        let transfer = try XCTUnwrap(
            document.move([id("a"), id("b"), id("c"), id("d")], pinned: [id("b"), id("d")], from: source, to: destination)
        )

        XCTAssertEqual(document.pins(in: destination), [Pin(photo: id("b"), cell: 0), Pin(photo: id("d"), cell: 1)])
        XCTAssertEqual(transfer.pinned, [id("b"), id("d")])
    }

    /// A sequence already held in the destination is not disturbed: the moved
    /// pins take the first cells nobody holds.
    func testMovedPinsSkipCellsAlreadyPinnedInTheDestination() throws {
        var (document, source, destination) = library(["a", "b", "x"])
        document.move([id("x")], pinned: [], from: source, to: destination)
        document.updatePins([Pin(photo: id("x"), cell: 1)], for: destination)

        document.move([id("a"), id("b")], pinned: [id("a"), id("b")], from: source, to: destination)

        XCTAssertEqual(Set(document.pins(in: destination)), [
            Pin(photo: id("x"), cell: 1),
            Pin(photo: id("a"), cell: 0),
            Pin(photo: id("b"), cell: 2),
        ])
    }

    /// Unpinned photographs leave their source pins behind, and the source's
    /// own pins on moved photographs go with the removal.
    func testSourcePinsOnMovedPhotographsGoAndOthersStay() throws {
        var (document, source, destination) = library(["a", "b"])
        document.updatePins([Pin(photo: id("a"), cell: 0), Pin(photo: id("b"), cell: 1)], for: source)

        document.move([id("a")], pinned: [id("a")], from: source, to: destination)

        XCTAssertEqual(document.pins(in: source), [Pin(photo: id("b"), cell: 1)])
    }

    /// A photograph can be in several collections. Already in the destination,
    /// it stays there once, and keeps the pin it has there.
    func testAPhotographAlreadyInTheDestinationIsNotDuplicated() throws {
        var (document, source, destination) = library(["a", "b"])
        document.add([id("a")], to: destination)
        document.updatePins([Pin(photo: id("a"), cell: 7)], for: destination)

        let transfer = try XCTUnwrap(
            document.move([id("a"), id("b")], pinned: [id("a")], from: source, to: destination)
        )

        XCTAssertEqual(names(document, destination), ["a", "b"])
        XCTAssertEqual(document.pins(in: destination), [Pin(photo: id("a"), cell: 7)])
        XCTAssertEqual(transfer.joined, [id("b")])
        XCTAssertEqual(transfer.pins, [])
        XCTAssertEqual(names(document, source), [])
    }

    /// From All Photos there is no collection to take them out of.
    func testFromAllPhotosItAddsAndRemovesNothing() throws {
        var (document, source, destination) = library(["a", "b", "c"])
        document.updatePins([Pin(photo: id("c"), cell: 4)], for: nil)

        let transfer = try XCTUnwrap(
            document.move([id("c"), id("a")], pinned: [id("c")], from: nil, to: destination)
        )

        XCTAssertEqual(names(document, source), ["a", "b", "c"])
        XCTAssertEqual(names(document, destination), ["c", "a"])
        XCTAssertEqual(document.pins(in: destination), [Pin(photo: id("c"), cell: 0)])
        XCTAssertEqual(document.pins(in: nil), [Pin(photo: id("c"), cell: 4)], "All Photos keeps its own pins")
        XCTAssertNil(transfer.removal)
    }

    /// A no-op must not land in the history as a step that undoes nothing.
    func testNothingToMoveReportsNothingToUndo() {
        var (document, source, destination) = library(["a"])
        XCTAssertNil(document.move([id("a")], pinned: [], from: source, to: source))
        XCTAssertNil(document.move([id("a")], pinned: [], from: source, to: UUID()))
        XCTAssertNil(document.move([id("a")], pinned: [], from: UUID(), to: destination))
        XCTAssertNil(document.move([id("zz")], pinned: [], from: source, to: destination))
        XCTAssertNil(document.move([], pinned: [], from: source, to: destination))

        document.add([id("a")], to: destination)
        XCTAssertNil(document.move([id("a")], pinned: [], from: nil, to: destination),
                     "already there, from All Photos, changes nothing")
    }

    // MARK: - Undo

    func testReversingPutsEverythingBackWhereItWas() throws {
        var (document, source, destination) = library(["a", "b", "c", "d", "e"])
        document.updatePins([Pin(photo: id("b"), cell: 1), Pin(photo: id("e"), cell: 9)], for: source)
        document.updatePins([Pin(photo: id("a"), cell: 0)], for: nil)
        let before = document

        let transfer = try XCTUnwrap(
            document.move([id("b"), id("d")], pinned: [id("b")], from: source, to: destination)
        )
        document.reverse(transfer)

        XCTAssertEqual(normalized(document), normalized(before))
        XCTAssertEqual(names(document, source), ["a", "b", "c", "d", "e"], "back at their indices")
    }

    func testReversingAMoveFromAllPhotosTakesOnlyWhatItAdded() throws {
        var (document, _, destination) = library(["a", "b"])
        document.add([id("a")], to: destination)
        document.updatePins([Pin(photo: id("a"), cell: 2)], for: destination)
        let before = document

        let transfer = try XCTUnwrap(document.move([id("a"), id("b")], pinned: [id("b")], from: nil, to: destination))
        document.reverse(transfer)

        XCTAssertEqual(normalized(document), normalized(before))
    }

    /// Undoing a move to a new collection leaves the collection, empty. It was
    /// made by the move, but deleting it is a separate decision.
    func testReversingLeavesADestinationCollectionInPlace() throws {
        var (document, source, _) = library(["a"])
        let fresh = document.addCollection(named: "New")

        let transfer = try XCTUnwrap(document.move([id("a")], pinned: [id("a")], from: source, to: fresh.id))
        document.reverse(transfer)

        XCTAssertTrue(document.collections.contains { $0.id == fresh.id })
        XCTAssertEqual(names(document, fresh.id), [])
        XCTAssertEqual(document.pins(in: fresh.id), [])
    }

    /// Redo asks again with what the transfer recorded, and lands where the
    /// first move did.
    func testRedoingReproducesTheMove() throws {
        var (document, source, destination) = library(["a", "b", "c"])
        document.updatePins([Pin(photo: id("c"), cell: 2)], for: source)

        let first = try XCTUnwrap(document.move([id("c"), id("a")], pinned: [id("c")], from: source, to: destination))
        let after = document
        document.reverse(first)
        let again = try XCTUnwrap(
            document.move(first.photographs, pinned: Set(first.pinned), from: first.source, to: first.destination)
        )

        XCTAssertEqual(normalized(document), normalized(after))
        XCTAssertEqual(again.joined, first.joined)
        XCTAssertEqual(again.pins, first.pins)
    }

    /// A move carries no reference, so it is not held to the ten reversible
    /// removals.
    func testAMoveIsNotCountedAsARemoval() throws {
        var (document, source, destination) = library(["a"])
        let transfer = try XCTUnwrap(document.move([id("a")], pinned: [], from: source, to: destination))
        XCTAssertFalse(Step(arrangement: Arrangement(), label: "Move", transfer: transfer).isRemoval)
    }

    /// Long random runs of moves and removals, undone and redone in stack order:
    /// every undo must return the library to exactly what it was before that
    /// step, and every redo to exactly what it was after.
    func testUndoAndRedoAreExactThroughRandomRuns() {
        let pool = (0..<24).map { reference("pool-\($0)") }

        for seed in UInt64(1)...25 {
            var rng = SeededGenerator(seed: seed)
            var document = LibraryDocument()
            for n in 0..<4 {
                let collection = document.addCollection(named: "c\(n)")
                document.add(pool.shuffled(using: &rng).prefix(8).map { $0 }, to: collection.id)
                let members = document.collections.last!.memberIDs
                document.updatePins(
                    members.prefix(3).enumerated().map { Pin(photo: $0.element, cell: $0.offset * 2) },
                    for: collection.id
                )
            }

            enum Change { case move(Transfer), removal(Restoration) }
            // Each entry: the change, and the library before and after it.
            var undo: [(Change, Normalized, Normalized)] = []
            var redo: [(Change, Normalized, Normalized)] = []

            for step in 0..<300 {
                let action = Int.random(in: 0..<4, using: &rng)
                let before = normalized(document)
                let ids = document.collections.map(\.id)
                let context = "seed \(seed), step \(step), action \(action)"

                switch action {
                case 0:
                    let source: UUID? = Bool.random(using: &rng) ? ids.randomElement(using: &rng) : nil
                    let destination = ids.randomElement(using: &rng)!
                    let candidates = source.map { s in document.collections.first { $0.id == s }!.memberIDs }
                        ?? document.references.map(\.id)
                    let photographs = Array(candidates.shuffled(using: &rng).prefix(Int.random(in: 1...4, using: &rng)))
                    let pinned = Set(photographs.filter { _ in Bool.random(using: &rng) })
                    if let transfer = document.move(photographs, pinned: pinned, from: source, to: destination) {
                        undo.append((.move(transfer), before, normalized(document)))
                        redo.removeAll()
                    }
                case 1:
                    guard let collection = document.collections.filter({ !$0.memberIDs.isEmpty }).randomElement(using: &rng)
                    else { break }
                    let ids = Set(collection.memberIDs.shuffled(using: &rng).prefix(2))
                    if let restoration = document.removeFromCollection(ids, collectionID: collection.id) {
                        undo.append((.removal(restoration), before, normalized(document)))
                        redo.removeAll()
                    }
                case 2:
                    guard let entry = undo.popLast() else { break }
                    switch entry.0 {
                    case .move(let transfer): document.reverse(transfer)
                    case .removal(let restoration): document.restore(restoration)
                    }
                    XCTAssertEqual(normalized(document), entry.1, "undo, \(context)")
                    redo.append(entry)
                default:
                    guard let entry = redo.popLast() else { break }
                    switch entry.0 {
                    case .move(let t):
                        document.move(t.photographs, pinned: Set(t.pinned), from: t.source, to: t.destination)
                    case .removal(let r):
                        document.removeFromCollection(Set(r.memberships.map(\.photo)), collectionID: r.collection)
                    }
                    XCTAssertEqual(normalized(document), entry.2, "redo, \(context)")
                    undo.append(entry)
                }

                let library = Set(document.references.map(\.id))
                let union = Set(document.collections.flatMap(\.memberIDs))
                XCTAssertEqual(library, union, context)
                if library != union { return }
            }
        }
    }

    // MARK: - Comparing

    /// The library with pins compared as sets: restoring appends pins rather than
    /// splicing them back, and their order carries no meaning.
    private struct Normalized: Equatable {
        let references: [ContentHash]
        let collections: [UUID: [ContentHash]]
        let pins: [UUID: Set<Pin>]
        let allPhotosPins: Set<Pin>
    }

    private func normalized(_ document: LibraryDocument) -> Normalized {
        Normalized(
            references: document.references.map(\.id),
            collections: Dictionary(uniqueKeysWithValues: document.collections.map { ($0.id, $0.memberIDs) }),
            pins: Dictionary(uniqueKeysWithValues: document.collections.map { ($0.id, Set($0.pins)) }),
            allPhotosPins: Set(document.allPhotosPins)
        )
    }
}
