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
        setPinned(!isPinned(cell: cell), at: cell)
    }

    /// Takes photographs out of the sheet and closes the gap, everything after
    /// shuffling up one place.
    ///
    /// Pinned frames move up too. That settles what a pin means: it holds a
    /// photograph across *rolls*, not at a fixed cell for ever — so a pin's cell
    /// follows its photograph rather than the photograph being stranded from its
    /// pin. Empty cells that were already there stay where they are; only the
    /// gap the removal made is closed.
    public mutating func removeClosingGaps(_ ids: Set<ContentHash>) {
        let capacity = slots.count
        var kept = slots.filter { slot in slot.map { !ids.contains($0) } ?? true }
        kept.append(contentsOf: repeatElement(nil, count: max(0, capacity - kept.count)))
        slots = Array(kept.prefix(capacity))

        var cellOf: [ContentHash: Int] = [:]
        for (cell, slot) in slots.enumerated() { if let slot { cellOf[slot] = cell } }

        pins = pins.compactMap { pin in
            if ids.contains(pin.photo) { return nil }
            // A pin for a photograph that is not on this sheet — held over from a
            // larger grid — is left exactly as it is.
            guard let cell = cellOf[pin.photo] else { return pin }
            return Pin(photo: pin.photo, cell: cell)
        }
    }

    /// Moves the photograph in one cell to another and pins it there — the drag.
    ///
    /// Onto an occupied cell it is a move within the sheet's order: the
    /// photograph comes out of its cell, the gap closes, and it goes back in at
    /// the target. Everything between the two cells shifts one place towards the
    /// cell it left — to the right when dragged back, to the left when dragged
    /// forward. Nothing leaves the sheet, and no cell becomes empty that was not
    /// empty already. It is a removal and an insertion composed, so it follows
    /// the removal rule for pins: a pin's cell follows its photograph.
    ///
    /// Onto an empty cell there is nothing to make room for, so the photograph is
    /// simply placed there and the cell it left is empty.
    ///
    /// Dropping it back where it started is a cancelled drag, not a pin.
    public mutating func move(from source: Int, to target: Int) {
        guard source != target,
              slots.indices.contains(source), slots.indices.contains(target),
              let photograph = slots[source]
        else { return }

        if slots[target] == nil {
            slots[target] = photograph
            slots[source] = nil
        } else {
            slots.remove(at: source)
            slots.insert(photograph, at: target)
        }

        var cellOf: [ContentHash: Int] = [:]
        for (cell, slot) in slots.enumerated() { if let slot { cellOf[slot] = cell } }
        pins = pins.map { pin in
            cellOf[pin.photo].map { Pin(photo: pin.photo, cell: $0) } ?? pin
        }

        // Putting a photograph somewhere is deciding where it goes, so it is
        // held there.
        pins.removeAll { $0.photo == photograph || $0.cell == target }
        pins.append(Pin(photo: photograph, cell: target))
    }

    /// The next cell holding a photograph, `step` cells at a time from `cell` —
    /// how the lightbox walks the sheet. Empty cells are passed over. `nil` at
    /// either end: the walk stops rather than wrapping, so the end of the
    /// sequence stays where it is.
    public func filledCell(from cell: Int, step: Int) -> Int? {
        guard step != 0 else { return nil }
        var next = cell + step
        while slots.indices.contains(next) {
            if slots[next] != nil { return next }
            next += step
        }
        return nil
    }

    /// The sheet as it would be after `move(from:to:)` — what a drag shows while
    /// it is still over the sheet, before anything is committed.
    public func moving(from source: Int, to target: Int) -> Arrangement {
        var copy = self
        copy.move(from: source, to: target)
        return copy
    }

    public mutating func setPinned(_ pinned: Bool, at cell: Int) {
        guard let photograph = photograph(at: cell) else { return }
        if pinned {
            guard !isPinned(cell: cell) else { return }
            pins.removeAll { $0.photo == photograph || $0.cell == cell }
            pins.append(Pin(photo: photograph, cell: cell))
        } else {
            pins.removeAll { $0.cell == cell && $0.photo == photograph }
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
