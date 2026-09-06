import XCTest
@testable import PhotomancyCore

final class HistoryTests: XCTestCase {

    func testStartsWithNothingToUndo() {
        let history = History("a")
        XCTAssertEqual(history.current, "a")
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testStepsBackAndForward() {
        var history = History("a")
        history.commit("b")
        history.commit("c")

        XCTAssertNotNil(history.undo())
        XCTAssertEqual(history.current, "b")
        XCTAssertNotNil(history.undo())
        XCTAssertEqual(history.current, "a")
        XCTAssertFalse(history.canUndo)

        XCTAssertNotNil(history.redo())
        XCTAssertEqual(history.current, "b")
        XCTAssertNotNil(history.redo())
        XCTAssertEqual(history.current, "c")
        XCTAssertFalse(history.canRedo)
    }

    func testUndoingPastTheStartIsHarmless() {
        var history = History("a")
        XCTAssertNil(history.undo())
        XCTAssertNil(history.redo())
        XCTAssertEqual(history.current, "a")
    }

    /// Undoing and then doing something else takes a different branch, and what
    /// was undone is gone.
    func testANewCommitDiscardsWhatWasUndone() {
        var history = History("a")
        history.commit("b")
        history.undo()
        XCTAssertTrue(history.canRedo)

        history.commit("z")
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.current, "z")
        history.undo()
        XCTAssertEqual(history.current, "a")
    }

    /// A step that changes nothing would appear broken when undone.
    func testCommittingAnIdenticalStateRecordsNothing() {
        var history = History("a")
        history.commit("a")
        XCTAssertFalse(history.canUndo)
        XCTAssertEqual(history.depth, 0)
    }

    func testTheHistoryIsBounded() {
        var history = History(0, limit: 5)
        for value in 1...50 { history.commit(value) }
        XCTAssertEqual(history.depth, 5)
        XCTAssertEqual(history.current, 50)

        for _ in 0..<5 { history.undo() }
        XCTAssertFalse(history.canUndo)
        XCTAssertEqual(history.current, 45)
    }

    func testResetClearsBothDirections() {
        var history = History("a")
        history.commit("b")
        history.undo()
        history.reset(to: "fresh")
        XCTAssertEqual(history.current, "fresh")
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    /// The one that matters: rolling repeatedly and stepping all the way back.
    func testUndoSpansManyRolls() {
        var history = History(0)
        for roll in 1...30 { history.commit(roll) }
        for expected in stride(from: 29, through: 0, by: -1) {
            XCTAssertNotNil(history.undo())
            XCTAssertEqual(history.current, expected)
        }
        XCTAssertFalse(history.canUndo)
    }

    /// Undo hands back the step it left, so a caller can reverse whatever that
    /// step did beyond changing the state.
    func testUndoAndRedoReturnTheStepInvolved() {
        var history = History("a")
        history.commit("b")
        XCTAssertEqual(history.undo(), "b", "the step being undone")
        XCTAssertEqual(history.redo(), "b", "the step being redone")
    }

    /// One kind of step can be bounded more tightly than the rest: arrangements
    /// stay deep and cheap, removals are kept to a handful. Everything older
    /// than the surviving window goes too, so undo never reaches a step that
    /// looks reversible and is not.
    func testTrimmingBoundsOneKindOfStepWithoutBoundingTheOthers() {
        var history = History(0)
        // Evens stand in for removals, odds for ordinary steps.
        for value in 1...20 { history.commit(value) }
        XCTAssertEqual(history.depth, 20)

        history.trimPast(toAtMost: 3, matching: { $0 % 2 == 0 })

        var removalsLeft = 0
        var depth = 0
        var walk = history
        while walk.undo() != nil {
            depth += 1
            if walk.current % 2 == 0 { removalsLeft += 1 }
        }
        XCTAssertLessThanOrEqual(removalsLeft, 3)
        XCTAssertGreaterThan(depth, 0, "ordinary steps survive the trim")
    }

    func testTrimmingLeavesAShortHistoryAlone() {
        var history = History(0)
        for value in 1...4 { history.commit(value) }
        history.trimPast(toAtMost: 10, matching: { _ in true })
        XCTAssertEqual(history.depth, 4)
    }
}
