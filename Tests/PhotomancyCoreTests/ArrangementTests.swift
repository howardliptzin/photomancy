import XCTest
@testable import PhotomancyCore

/// Deterministic, so "it moved" and "it stayed" are assertions rather than
/// impressions.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

final class ArrangementTests: XCTestCase {

    private func library(_ count: Int) -> [PhotoReference] {
        (0..<count).map { index in
            PhotoReference(
                id: ContentHasher.hash(Data("photo-\(index)".utf8)),
                displayName: "photo-\(index).jpg",
                fileSize: 1,
                pixelWidth: 6000,
                pixelHeight: 4000,
                bookmark: Data()
            )
        }
    }

    private func roll(_ photographs: [PhotoReference], pins: [Pin] = [], cells: Int, seed: UInt64 = 1) -> Arrangement {
        var generator = SeededGenerator(seed: seed)
        return Arrangement.rolled(photographs: photographs, pins: pins, cellCount: cells, using: &generator)
    }

    // MARK: - Dealing

    func testEveryCellIsFilledWhenThereAreEnoughPhotographs() {
        let arrangement = roll(library(20), cells: 20)
        XCTAssertEqual(arrangement.slots.count, 20)
        XCTAssertTrue(arrangement.slots.allSatisfy { $0 != nil })
    }

    /// A duplicate reads as a bug rather than as a choice.
    func testAPhotographIsNeverPlacedTwice() {
        for seed in UInt64(1)...20 {
            let placed = roll(library(30), cells: 20, seed: seed).slots.compactMap { $0 }
            XCTAssertEqual(Set(placed).count, placed.count, "seed \(seed)")
        }
    }

    func testFewerPhotographsThanCellsLeavesCellsEmpty() {
        let arrangement = roll(library(6), cells: 20)
        XCTAssertEqual(arrangement.slots.compactMap { $0 }.count, 6)
        XCTAssertEqual(arrangement.slots.filter { $0 == nil }.count, 14)
    }

    /// More photographs than cells is the good case: each roll draws a different
    /// subset, which is more surprise per roll.
    func testEachRollSamplesADifferentSubsetFromABiggerPool() {
        let photographs = library(60)
        var seen: Set<ContentHash> = []
        for seed in UInt64(1)...12 {
            seen.formUnion(roll(photographs, cells: 12, seed: seed).slots.compactMap { $0 })
        }
        XCTAssertGreaterThan(seen.count, 12, "rolls should reach beyond one screenful")
    }

    func testAnEmptyGridIsHandled() {
        XCTAssertTrue(roll(library(10), cells: 0).slots.isEmpty)
    }

    func testAnEmptyLibraryLeavesEveryCellEmpty() {
        let arrangement = roll([], cells: 12)
        XCTAssertEqual(arrangement.slots.count, 12)
        XCTAssertTrue(arrangement.slots.allSatisfy { $0 == nil })
    }

    // MARK: - Pins

    func testAPinnedPhotographStaysInItsCellAcrossEveryRoll() {
        let photographs = library(40)
        let held = photographs[7].id
        let pins = [Pin(photo: held, cell: 5)]

        for seed in UInt64(1)...25 {
            let arrangement = roll(photographs, pins: pins, cells: 20, seed: seed)
            XCTAssertEqual(arrangement.photograph(at: 5), held, "seed \(seed)")
            XCTAssertTrue(arrangement.isPinned(cell: 5))
        }
    }

    func testUnpinnedPhotographsActuallyMove() {
        let photographs = library(20)
        let first = roll(photographs, cells: 20, seed: 1)
        let second = roll(photographs, cells: 20, seed: 2)
        XCTAssertNotEqual(first.slots, second.slots)
    }

    /// A pin outside the current grid is ignored, not discarded: shrinking to
    /// 3 × 2 and growing back must not lose what was held in cell 15.
    func testAPinOutsideTheGridIsIgnoredButKept() {
        let photographs = library(20)
        let pins = [Pin(photo: photographs[3].id, cell: 15)]

        let small = roll(photographs, pins: pins, cells: 6)
        XCTAssertEqual(small.slots.count, 6)
        XCTAssertEqual(small.pins, pins, "still remembered")

        let large = roll(photographs, pins: pins, cells: 20)
        XCTAssertEqual(large.photograph(at: 15), photographs[3].id, "honoured again")
    }

    func testAPinToAPhotographNoLongerInTheLibraryIsIgnored() {
        let photographs = library(10)
        let ghost = ContentHasher.hash(Data("gone".utf8))
        let arrangement = roll(photographs, pins: [Pin(photo: ghost, cell: 2)], cells: 10)
        XCTAssertNotEqual(arrangement.photograph(at: 2), ghost)
        XCTAssertEqual(arrangement.slots.compactMap { $0 }.count, 10)
    }

    func testTogglingPinsAndReleases() {
        var arrangement = roll(library(12), cells: 12)
        XCTAssertFalse(arrangement.isPinned(cell: 3))
        arrangement.togglePin(at: 3)
        XCTAssertTrue(arrangement.isPinned(cell: 3))
        XCTAssertEqual(arrangement.pins.count, 1)
        arrangement.togglePin(at: 3)
        XCTAssertFalse(arrangement.isPinned(cell: 3))
        XCTAssertTrue(arrangement.pins.isEmpty)
    }

    /// One photograph is held in one place. Pinning it somewhere new releases
    /// wherever it was, so it can never be pinned to two cells at once.
    func testPinningAPhotographElsewhereReleasesItsOldCell() {
        let photographs = library(12)
        var arrangement = Arrangement(slots: photographs.map { $0.id }, pins: [])
        arrangement.togglePin(at: 2)

        var moved = Arrangement(
            slots: [photographs[2].id] + photographs.dropFirst().map { $0.id },
            pins: arrangement.pins
        )
        moved.togglePin(at: 0)

        XCTAssertEqual(moved.pins.count, 1)
        XCTAssertEqual(moved.pins.first?.cell, 0)
    }

    func testAnEmptyCellCannotBePinned() {
        var arrangement = roll(library(3), cells: 12)
        arrangement.togglePin(at: 11)
        XCTAssertTrue(arrangement.pins.isEmpty)
        XCTAssertFalse(arrangement.isPinned(cell: 11))
    }

    func testUnpinAllReleasesEverything() {
        var arrangement = roll(library(12), cells: 12)
        arrangement.togglePin(at: 1)
        arrangement.togglePin(at: 4)
        XCTAssertEqual(arrangement.pins.count, 2)
        arrangement.unpinAll()
        XCTAssertTrue(arrangement.pins.isEmpty)
    }

    /// Every cell pinned means a roll changes nothing at all.
    func testAFullyPinnedSheetIsUnchangedByARoll() {
        let photographs = library(6)
        let pins = photographs.enumerated().map { Pin(photo: $0.element.id, cell: $0.offset) }
        let first = roll(photographs, pins: pins, cells: 6, seed: 1)
        let second = roll(photographs, pins: pins, cells: 6, seed: 99)
        XCTAssertEqual(first.slots, second.slots)
    }

    func testTheSameSeedGivesTheSameRoll() {
        XCTAssertEqual(roll(library(30), cells: 20, seed: 42).slots,
                       roll(library(30), cells: 20, seed: 42).slots)
    }

    // MARK: - Dragging to a cell

    private func sheet(_ count: Int, cells: Int? = nil, pins: [Pin] = []) -> (Arrangement, [ContentHash]) {
        let ids = library(count).map(\.id)
        let slots: [ContentHash?] = ids + Array(repeating: nil, count: max(0, (cells ?? count) - count))
        return (Arrangement(slots: slots, pins: pins), ids)
    }

    func testDraggingBackShiftsTheCellsBetweenOnePlaceRight() {
        var (arrangement, id) = sheet(6)
        arrangement.move(from: 4, to: 1)
        XCTAssertEqual(arrangement.slots, [id[0], id[4], id[1], id[2], id[3], id[5]])
    }

    func testDraggingForwardShiftsTheCellsBetweenOnePlaceLeft() {
        var (arrangement, id) = sheet(6)
        arrangement.move(from: 1, to: 4)
        XCTAssertEqual(arrangement.slots, [id[0], id[2], id[3], id[4], id[1], id[5]])
    }

    func testTheDroppedPhotographIsPinnedWhereItLands() {
        var (arrangement, id) = sheet(6)
        arrangement.move(from: 4, to: 1)
        XCTAssertTrue(arrangement.isPinned(cell: 1))
        XCTAssertEqual(arrangement.pins, [Pin(photo: id[4], cell: 1)])
    }

    /// Nothing leaves the sheet and nothing is duplicated.
    func testAMoveKeepsEveryPhotographExactlyOnce() {
        var (arrangement, _) = sheet(12)
        let before = arrangement.slots
        arrangement.move(from: 11, to: 0)
        XCTAssertEqual(Set(arrangement.slots.compactMap { $0 }), Set(before.compactMap { $0 }))
        XCTAssertEqual(arrangement.slots.count, before.count)
    }

    /// The removal rule: a pin holds a photograph, so its cell follows it.
    func testPinsInTheShiftedRunFollowTheirPhotographs() {
        let ids = library(6).map(\.id)
        var (arrangement, _) = sheet(6, pins: [Pin(photo: ids[2], cell: 2), Pin(photo: ids[5], cell: 5)])
        arrangement.move(from: 4, to: 1)
        XCTAssertTrue(arrangement.isPinned(cell: 3), "photograph 2 moved right and took its pin")
        XCTAssertFalse(arrangement.isPinned(cell: 2))
        XCTAssertTrue(arrangement.isPinned(cell: 5), "outside the run, untouched")
    }

    func testMovingAPinnedPhotographKeepsItPinnedAtItsNewCell() {
        let ids = library(6).map(\.id)
        var (arrangement, _) = sheet(6, pins: [Pin(photo: ids[4], cell: 4)])
        arrangement.move(from: 4, to: 1)
        XCTAssertEqual(arrangement.pins, [Pin(photo: ids[4], cell: 1)])
    }

    /// Empty cells only ever trail, so a drop past the last photograph lands at
    /// the end of the sequence rather than parking where the pointer was.
    func testDroppingPastTheLastPhotographLandsAtTheEnd() {
        var (arrangement, id) = sheet(3, cells: 6)
        arrangement.move(from: 0, to: 4)
        XCTAssertEqual(arrangement.slots, [id[1], id[2], id[0], nil, nil, nil])
        XCTAssertTrue(arrangement.isPinned(cell: 2))
        XCTAssertTrue(arrangement.emptiesOnlyTrail)
    }

    // MARK: - Dragging a selection

    /// The run starts at the cell it was dropped on, in sheet order.
    func testARunLandsAtTheCellItWasDroppedOn() {
        var (arrangement, id) = sheet(6)
        arrangement.move([id[0], id[1]], to: 4)
        XCTAssertEqual(arrangement.slots, [id[2], id[3], id[4], id[5], id[0], id[1]])
    }

    func testARunDraggedBackPushesTheOthersRight() {
        var (arrangement, id) = sheet(6)
        arrangement.move([id[3], id[5]], to: 1)
        XCTAssertEqual(arrangement.slots, [id[0], id[3], id[5], id[1], id[2], id[4]])
    }

    /// Order is the sheet's, not the order the caller happened to hand over.
    func testARunTravelsInSheetOrder() {
        var (arrangement, id) = sheet(6)
        arrangement.move([id[4], id[1]], to: 0)
        XCTAssertEqual(arrangement.slots, [id[1], id[4], id[0], id[2], id[3], id[5]])
    }

    func testEveryPhotographInARunIsPinnedWhereItLands() {
        var (arrangement, id) = sheet(6)
        arrangement.move([id[0], id[1]], to: 3)
        XCTAssertEqual(arrangement.pins.count, 2)
        XCTAssertTrue(arrangement.isPinned(cell: 3))
        XCTAssertTrue(arrangement.isPinned(cell: 4))
        XCTAssertEqual(arrangement.photograph(at: 3), id[0])
        XCTAssertEqual(arrangement.photograph(at: 4), id[1])
    }

    func testARunKeepsEveryPhotographExactlyOnce() {
        var (arrangement, id) = sheet(12)
        let before = arrangement.slots.compactMap { $0 }
        arrangement.move([id[9], id[2], id[11]], to: 5)
        XCTAssertEqual(Set(arrangement.slots.compactMap { $0 }), Set(before))
        XCTAssertEqual(arrangement.slots.compactMap { $0 }.count, before.count)
    }

    func testDroppingARunWhereItAlreadyIsChangesNothing() {
        var (arrangement, id) = sheet(6)
        let before = arrangement
        arrangement.move([id[0], id[1], id[2]], to: 0)
        XCTAssertEqual(arrangement, before, "a cancelled drag pins nothing")
    }

    func testARunDroppedPastTheLastPhotographLandsAtTheEnd() {
        var (arrangement, id) = sheet(4, cells: 8)
        arrangement.move([id[0], id[1]], to: 6)
        XCTAssertEqual(arrangement.slots, [id[2], id[3], id[0], id[1], nil, nil, nil, nil])
        XCTAssertTrue(arrangement.emptiesOnlyTrail)
    }

    // MARK: - Empty cells only ever trail

    /// The invariant, against every operation in any order: an empty cell always
    /// means the collection ran out, never that something was parked past it.
    func testEveryOperationLeavesEmptyCellsAtTheEnd() {
        let photographs = library(14)
        for seed in UInt64(1)...40 {
            var generator = SeededGenerator(seed: seed)
            var arrangement = roll(photographs, cells: 20, seed: seed)
            for step in 0..<12 {
                let live = arrangement.slots.compactMap { $0 }
                switch step % 4 {
                case 0:
                    if let photograph = live.randomElement(using: &generator),
                       let cell = arrangement.slots.firstIndex(where: { $0 == photograph }) {
                        arrangement.move(from: cell, to: Int.random(in: 0..<20, using: &generator))
                    }
                case 1:
                    let run = live.shuffled(using: &generator).prefix(3)
                    arrangement.move(Array(run), to: Int.random(in: 0..<20, using: &generator))
                case 2:
                    if let victim = live.randomElement(using: &generator) {
                        arrangement.removeClosingGaps([victim])
                    }
                default:
                    arrangement = Arrangement.rolled(
                        photographs: photographs,
                        pins: arrangement.pins,
                        cellCount: 20,
                        using: &generator
                    )
                }
                XCTAssertTrue(
                    arrangement.emptiesOnlyTrail,
                    "seed \(seed), step \(step): \(arrangement.slots.map { $0 == nil ? "-" : "#" }.joined())"
                )
            }
        }
    }

    /// A pin held over from a larger grid can sit past everything the collection
    /// can fill. It is honoured, then the sheet closes up and the pin follows.
    func testAPinBeyondTheCollectionDoesNotStrandEmptyCells() {
        let photographs = library(4)
        let held = photographs[2].id
        let arrangement = roll(photographs, pins: [Pin(photo: held, cell: 15)], cells: 20)
        XCTAssertTrue(arrangement.emptiesOnlyTrail)
        XCTAssertEqual(arrangement.slots.compactMap { $0 }.count, 4)
        let landed = arrangement.slots.firstIndex(where: { $0 == held })
        XCTAssertNotNil(landed)
        XCTAssertEqual(arrangement.pins.first(where: { $0.photo == held })?.cell, landed)
    }

    func testDroppingBackWhereItStartedChangesNothing() {
        var (arrangement, _) = sheet(6)
        let before = arrangement
        arrangement.move(from: 2, to: 2)
        XCTAssertEqual(arrangement, before)
    }

    func testDraggingAnEmptyCellOrOffTheSheetChangesNothing() {
        var (arrangement, _) = sheet(3, cells: 6)
        let before = arrangement
        arrangement.move(from: 5, to: 0)
        arrangement.move(from: 0, to: 6)
        arrangement.move(from: -1, to: 2)
        XCTAssertEqual(arrangement, before)
    }

    /// The point of pinning on drop: the next roll leaves it where it was put.
    func testTheNextRollHoldsTheDroppedPhotograph() {
        let photographs = library(30)
        var arrangement = roll(photographs, cells: 20, seed: 3)
        let dragged = arrangement.photograph(at: 17)
        arrangement.move(from: 17, to: 2)
        for seed in UInt64(1)...10 {
            let next = roll(photographs, pins: arrangement.pins, cells: 20, seed: seed)
            XCTAssertEqual(next.photograph(at: 2), dragged, "seed \(seed)")
        }
    }

    // MARK: - Walking the sheet in the lightbox

    func testTheLightboxWalkPassesOverEmptyCells() {
        let ids = library(3).map(\.id)
        let arrangement = Arrangement(slots: [ids[0], nil, nil, ids[1], nil, ids[2]])
        XCTAssertEqual(arrangement.filledCell(from: 0, step: 1), 3)
        XCTAssertEqual(arrangement.filledCell(from: 3, step: 1), 5)
        XCTAssertEqual(arrangement.filledCell(from: 5, step: -1), 3)
        XCTAssertEqual(arrangement.filledCell(from: 3, step: -1), 0)
    }

    /// The end of the sequence stays the end.
    func testTheLightboxWalkStopsAtEitherEndRatherThanWrapping() {
        let (arrangement, _) = sheet(3, cells: 5)
        XCTAssertNil(arrangement.filledCell(from: 2, step: 1), "only empty cells after the last photograph")
        XCTAssertNil(arrangement.filledCell(from: 0, step: -1))
        XCTAssertNil(arrangement.filledCell(from: 1, step: 0))
    }
}
