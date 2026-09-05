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
}
