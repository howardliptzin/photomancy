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
    /// pin. The photographs left keep their order and close up from the front,
    /// which is the sheet's invariant: empty cells only ever trail.
    public mutating func removeClosingGaps(_ ids: Set<ContentHash>) {
        let capacity = slots.count
        let kept = slots.compactMap { $0 }.filter { !ids.contains($0) }
        slots = fill(kept, capacity: capacity)

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
    public mutating func move(from source: Int, to target: Int) {
        guard source != target, let photograph = photograph(at: source) else { return }
        move([photograph], to: target)
    }

    /// Moves photographs to a cell and pins them there, in sheet order — the
    /// drag, for one frame or for a whole selection.
    ///
    /// It is a removal and an insertion composed: the carried photographs come
    /// out, the sheet closes up, and they go back in as one run starting at the
    /// cell they were dropped on. Everything between shifts to make room — to
    /// the right when the run is dragged back, to the left when it is dragged
    /// forward. Nothing leaves the sheet: the count is conserved, so no drop can
    /// push a photograph off the end.
    ///
    /// Dropped past the last photograph — onto the empty cells at the end — the
    /// run lands at the end of the sequence rather than parking where the pointer
    /// was. **Empty cells only ever trail**, on a sheet as in a collection, and
    /// that is what `emptiesOnlyTrail` asserts.
    ///
    /// Pins follow the removal rule: a pin's cell follows its photograph. Being
    /// put somewhere is deciding where it goes, so each photograph moved is
    /// held there.
    ///
    /// Dropped where it already is, the run is a cancelled drag: nothing moves
    /// and nothing is pinned.
    public mutating func move(_ photographs: [ContentHash], to target: Int) {
        let carriedIds = Set(photographs)
        // Sheet order, and only what is actually on this sheet — the caller may
        // hand over a selection in any order.
        let carried = slots.compactMap { $0 }.filter { carriedIds.contains($0) }
        // A drop in the dead space beyond the grid is not a drop on a cell.
        guard !carried.isEmpty, slots.indices.contains(target) else { return }

        let capacity = slots.count
        var kept = slots.compactMap { $0 }.filter { !carriedIds.contains($0) }
        kept.insert(contentsOf: carried, at: min(target, kept.count))

        let next = fill(kept, capacity: capacity)
        guard next != slots else { return }
        slots = next

        var cellOf: [ContentHash: Int] = [:]
        for (cell, slot) in slots.enumerated() { if let slot { cellOf[slot] = cell } }
        pins = pins.map { pin in
            cellOf[pin.photo].map { Pin(photo: pin.photo, cell: $0) } ?? pin
        }

        let landed = Set(carried.compactMap { cellOf[$0] })
        // A pin held over from a larger grid keeps its cell, so it can still
        // collide with where the run landed. Its photograph is not on this
        // sheet; the run's is.
        pins.removeAll { carriedIds.contains($0.photo) || landed.contains($0.cell) }
        for photograph in carried {
            guard let cell = cellOf[photograph] else { continue }
            pins.append(Pin(photo: photograph, cell: cell))
        }
    }

    /// Photographs from the front, empty cells after them — the one shape a
    /// sheet's slots are ever in.
    private func fill(_ photographs: [ContentHash], capacity: Int) -> [ContentHash?] {
        let placed = photographs.prefix(capacity).map { Optional($0) }
        return placed + repeatElement(nil, count: max(0, capacity - placed.count))
    }

    /// The sheet's invariant: no photograph sits after an empty cell.
    ///
    /// Every operation preserves it — a roll fills from the front, a removal
    /// closes up, a drag re-inserts — so an empty cell always means "the
    /// collection ran out", never "something was parked past here".
    public var emptiesOnlyTrail: Bool {
        let firstEmpty = slots.firstIndex(where: { $0 == nil }) ?? slots.count
        return slots[firstEmpty...].allSatisfy { $0 == nil }
    }

    /// Closes up without taking anything out, and carries pins along.
    private mutating func closeGaps() {
        removeClosingGaps([])
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

    /// The same, for a run of photographs: the preview a multiple drag shows.
    public func moving(_ photographs: [ContentHash], to target: Int) -> Arrangement {
        var copy = self
        copy.move(photographs, to: target)
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

        var rolled = Arrangement(slots: slots, pins: pins)
        // A pin held over from a larger grid can sit past everything the
        // collection can fill — pinned at cell 15 with six photographs. Honour
        // it, then close up, so empty cells still only trail; the pin follows
        // its photograph to where it actually landed, as it does on a removal.
        if !rolled.emptiesOnlyTrail {
            rolled.closeGaps()
        }
        return rolled
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
