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

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = past.popLast() else { return false }
        future.append(current)
        current = previous
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = future.popLast() else { return false }
        past.append(current)
        current = next
        return true
    }
}
