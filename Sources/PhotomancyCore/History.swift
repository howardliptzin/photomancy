import Foundation

/// Steps backward and forward through states.
///
/// Undo spans shuffles. That is the whole point: if chance is the method, the
/// photographer has to be able to gamble freely — roll past something good and
/// get it back. Without it every roll carries a small hesitation and the loop
/// stops being free.
public struct History<Value: Equatable & Sendable>: Sendable {

    public private(set) var current: Value
    private var past: [Value] = []
    private var future: [Value] = []
    private let limit: Int

    /// Bounded so a long session does not grow without end. Two hundred
    /// arrangements is far more than anyone steps back through, and costs a few
    /// kilobytes.
    public init(_ value: Value, limit: Int = 200) {
        self.current = value
        self.limit = max(1, limit)
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var depth: Int { past.count }
    /// The step undo would reverse, for naming it in a menu.
    public var pendingUndo: Value? { past.isEmpty ? nil : current }
    /// The step redo would reapply.
    public var pendingRedo: Value? { future.last }

    /// Records a new state. Anything that had been undone is discarded — the
    /// person took a different branch.
    ///
    /// A state identical to the current one is not recorded: it would put a step
    /// in the history that appears to do nothing when undone, which reads as
    /// broken rather than as a no-op.
    public mutating func commit(_ value: Value) {
        guard value != current else { return }
        past.append(current)
        if past.count > limit { past.removeFirst(past.count - limit) }
        current = value
        future.removeAll()
    }

    /// Replaces the current state without recording a step — for changes that
    /// are not the person's doing, such as a library reload.
    public mutating func reset(to value: Value) {
        current = value
        past.removeAll()
        future.removeAll()
    }

    /// Steps back, returning the state that *was* current — the step being
    /// undone — so a caller can reverse whatever it did beyond the state itself.
    /// `nil` when there was nothing to undo.
    @discardableResult
    public mutating func undo() -> Value? {
        guard let previous = past.popLast() else { return nil }
        let undone = current
        future.append(current)
        current = previous
        return undone
    }

    /// Steps forward, returning the state that has *become* current — the step
    /// being redone. `nil` when there was nothing to redo.
    @discardableResult
    public mutating func redo() -> Value? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        current = next
        return next
    }

    /// Drops the oldest history until at most `count` of the remaining steps
    /// match.
    ///
    /// Lets one kind of step be bounded more tightly than the rest: ordinary
    /// arrangements are cheap and stay 200 deep, while steps holding something
    /// to restore are kept to a handful. Everything older than the surviving
    /// window goes too, so undo never reaches a step that looks reversible and
    /// is not.
    public mutating func trimPast(toAtMost count: Int, matching predicate: (Value) -> Bool) {
        guard count >= 0 else { return }
        var seen = 0
        for index in stride(from: past.count - 1, through: 0, by: -1) where predicate(past[index]) {
            seen += 1
            if seen > count {
                past.removeFirst(index + 1)
                return
            }
        }
    }
}
