import Foundation

/// One state of the sheet: what is in each cell, and what is held there.
///
/// Not persisted. Only the pins are — restoring a whole arrangement across
/// launches is deliberately not built, because a photograph whose position
/// mattered should have been pinned, and being taught that by the app costs
/// nothing.
public struct Arrangement: Sendable, Equatable {

    /// One entry per cell, in the same order `layout()` returns rectangles.
    /// `nil` is an empty cell — background and nothing else.
    public private(set) var slots: [ContentHash?]

    /// Photographs held in place across rolls. Kept whole even when a pin falls
    /// outside the current grid: shrinking to 3 × 2 and growing back to 5 × 4
    /// should not quietly discard what was pinned in cell 15.
    public private(set) var pins: [Pin]

    public init(slots: [ContentHash?] = [], pins: [Pin] = []) {
        self.slots = slots
        self.pins = pins
    }

    public var cellCount: Int { slots.count }

    public func photograph(at cell: Int) -> ContentHash? {
        slots.indices.contains(cell) ? slots[cell] : nil
    }

    public func isPinned(cell: Int) -> Bool {
        guard let photograph = photograph(at: cell) else { return false }
        return pins.contains { $0.cell == cell && $0.photo == photograph }
    }

    public var pinnedCells: Set<Int> {
        Set(pins.filter { slots.indices.contains($0.cell) }.map(\.cell))
    }

    /// Holds whatever is in that cell, or lets it go. An empty cell cannot be
    /// pinned — there is nothing to hold.
    public mutating func togglePin(at cell: Int) {
        guard let photograph = photograph(at: cell) else { return }
        if isPinned(cell: cell) {
            pins.removeAll { $0.cell == cell && $0.photo == photograph }
        } else {
            // One photograph is held in one place; pinning it somewhere new
            // releases wherever it was.
            pins.removeAll { $0.photo == photograph || $0.cell == cell }
            pins.append(Pin(photo: photograph, cell: cell))
        }
    }

    public mutating func unpinAll() {
        pins.removeAll()
    }

    // MARK: - Rolling

    /// A fresh arrangement: pinned photographs stay where they are, everything
    /// else is dealt again.
    ///
    /// More photographs than cells is the good case, not a shortfall — each roll
    /// draws a different subset, which is more surprise per roll. Fewer leaves
    /// cells empty. A photograph is never placed twice: a duplicate reads as a
    /// bug rather than as a choice.
    public static func rolled<G: RandomNumberGenerator>(
        photographs: [PhotoReference],
        pins: [Pin],
        cellCount: Int,
        using generator: inout G
    ) -> Arrangement {
        guard cellCount > 0 else { return Arrangement(slots: [], pins: pins) }

        var slots = [ContentHash?](repeating: nil, count: cellCount)
        let library = Set(photographs.map(\.id))
        var placed: Set<ContentHash> = []

        for pin in pins {
            guard slots.indices.contains(pin.cell),
                  library.contains(pin.photo),
                  slots[pin.cell] == nil,
                  !placed.contains(pin.photo)
            else { continue }
            slots[pin.cell] = pin.photo
            placed.insert(pin.photo)
        }

        var pool = photographs.map(\.id).filter { !placed.contains($0) }
        pool.shuffle(using: &generator)

        var deal = pool.makeIterator()
        for cell in slots.indices where slots[cell] == nil {
            guard let next = deal.next() else { break }
            slots[cell] = next
        }

        return Arrangement(slots: slots, pins: pins)
    }

    public static func rolled(
        photographs: [PhotoReference],
        pins: [Pin],
        cellCount: Int
    ) -> Arrangement {
        var generator = SystemRandomNumberGenerator()
        return rolled(photographs: photographs, pins: pins, cellCount: cellCount, using: &generator)
    }
}
