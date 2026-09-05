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

        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.current, "b")
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.current, "a")
        XCTAssertFalse(history.canUndo)

        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.current, "b")
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.current, "c")
        XCTAssertFalse(history.canRedo)
    }

    func testUndoingPastTheStartIsHarmless() {
        var history = History("a")
        XCTAssertFalse(history.undo())
        XCTAssertFalse(history.redo())
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
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.current, expected)
        }
        XCTAssertFalse(history.canUndo)
    }
}
