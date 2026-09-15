import Foundation

/// A photograph held in a particular cell across rolls.
///
/// Stored as photograph-and-cell rather than as a flag, so pinned frames come back
/// exactly where they were left after a quit. The unpinned ones re-roll, which is
/// the intended behaviour and not a shortfall.
public struct Pin: Codable, Sendable, Hashable {
    public let photo: ContentHash
    public var cell: Int
    public init(photo: ContentHash, cell: Int) {
        self.photo = photo
        self.cell = cell
    }
}

/// The shape of a cell, chosen per collection.
public enum CellShape: String, Codable, Sendable, Hashable, CaseIterable {
    case square
    case threeByTwo
    case fourByThree
    /// The ratio shared by more than half the collection — the default.
    ///
    /// Where no ratio holds a majority it falls back to square, which is the
    /// right answer for exactly that case: square is the only shape where a
    /// photograph and its transpose occupy the same area, and the minimax
    /// choice under random placement. A collection of mixed orientation has
    /// no majority ratio and lands on square by arithmetic rather than by
    /// special-casing.
    case derivedFromCollection

    /// Width ÷ height, resolved against the collection it belongs to.
    /// Pure, so `layout()` can be tested without a library.
    public func aspect(for photographs: [PhotoReference]) -> Double {
        switch self {
        case .square: 1
        case .threeByTwo: 3.0 / 2.0
        case .fourByThree: 4.0 / 3.0
        case .derivedFromCollection: CellShape.majorityAspect(of: photographs) ?? 1
        }
    }

    /// The aspect shared by strictly more than half the collection, or `nil`.
    ///
    /// Ratios are clustered with a tolerance because a frame that has been
    /// straightened or exported at an odd size is still a 3:2 frame; without
    /// it, one stray pixel would split a cluster and lose the majority.
    public static func majorityAspect(
        of photographs: [PhotoReference],
        tolerance: Double = 0.02
    ) -> Double? {
        guard !photographs.isEmpty else { return nil }
        var clusters: [(aspect: Double, count: Int)] = []
        for photograph in photographs {
            let aspect = photograph.aspectRatio
            if let index = clusters.firstIndex(where: {
                abs($0.aspect - aspect) / $0.aspect <= tolerance
            }) {
                clusters[index].count += 1
            } else {
                clusters.append((aspect, 1))
            }
        }
        guard let largest = clusters.max(by: { $0.count < $1.count }) else { return nil }
        // Strictly more than half — "+51%", not "the most common".
        return largest.count * 2 > photographs.count ? largest.aspect : nil
    }
}



extension CellShape {

    /// How the cell-shape menu names this shape. A derived shape says what it
    /// resolved to — "Auto · 3:2" — so a shape that re-derives on import is at
    /// least visible.
    public func menuTitle(derivedAspect: Double) -> String {
        switch self {
        case .square: "Square"
        case .threeByTwo: "3:2"
        case .fourByThree: "4:3"
        case .derivedFromCollection: "Auto · \(CellShape.ratioName(derivedAspect))"
        }
    }

    /// Width ÷ height as photographers say it — 3:2, 4:3, 2:3 — within the same
    /// tolerance the majority uses. An unfamiliar ratio is given against 1.
    public static func ratioName(_ aspect: Double, tolerance: Double = 0.02) -> String {
        guard aspect.isFinite, aspect > 0 else { return "1:1" }
        let familiar = [(1, 1), (3, 2), (2, 3), (4, 3), (3, 4), (5, 4), (4, 5),
                        (7, 5), (5, 7), (16, 9), (9, 16), (2, 1), (1, 2)]
        for (width, height) in familiar {
            let ratio = Double(width) / Double(height)
            if abs(aspect - ratio) / ratio <= tolerance { return "\(width):\(height)" }
        }
        return String(format: "%.2f:1", aspect)
    }
}

/// 5 × 4 is a starting point, not a constraint.
///
/// 8 × 8 at a 1 px gap and 3 × 2 at 4 px are both ordinary uses. What a grid
/// costs on paper is a print-time question and never a reason to bound what
/// can be played with on screen.

/// How a sheet is set up. Persisted per collection, including for All Photos,
/// which carries its own settings and its own pins like any other collection.
public struct SheetSettings: Codable, Sendable, Hashable {

    public var columns: Int
    public var rows: Int
    /// Pixels on screen. On paper it is proportional, not absolute: printing
    /// scales the whole sheet uniformly, so the physical gap is
    /// `gap ÷ window width × page width` and changes with the window.
    public var gap: Double
    public var backgroundHex: String
    public var cellShape: CellShape
    /// The sheet itself. `CellShape.matchPage` resolves against this.
    public var paper: Paper

    public init(
        columns: Int = 5,
        rows: Int = 4,
        gap: Double = 12,
        backgroundHex: String = "#FFFFFF",
        cellShape: CellShape = .derivedFromCollection,
        paper: Paper = Paper()
    ) {
        self.columns = columns
        self.rows = rows
        self.gap = gap
        self.backgroundHex = backgroundHex
        self.cellShape = cellShape
        self.paper = paper
    }

    enum CodingKeys: String, CodingKey {
        case columns, rows, gap, backgroundHex, cellShape, paper
    }

    /// Every field falls back to its default when the key is absent.
    ///
    /// Settings are the part of the store that grows — this one gained
    /// `cellShape` after libraries had already been written. Synthesised
    /// decoding would have thrown on the missing key, and `LibraryStore.load()`
    /// refuses to overwrite a library it could not read, so a person would have
    /// opened the app to an empty grid and a file that was perfectly intact.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SheetSettings()
        columns = try container.decodeIfPresent(Int.self, forKey: .columns) ?? fallback.columns
        rows = try container.decodeIfPresent(Int.self, forKey: .rows) ?? fallback.rows
        gap = try container.decodeIfPresent(Double.self, forKey: .gap) ?? fallback.gap
        backgroundHex = try container.decodeIfPresent(String.self, forKey: .backgroundHex) ?? fallback.backgroundHex
        cellShape = try container.decodeIfPresent(CellShape.self, forKey: .cellShape) ?? fallback.cellShape
        paper = try container.decodeIfPresent(Paper.self, forKey: .paper) ?? fallback.paper
    }
}

/// An app-managed list of references. Not a folder — a photograph can be in
/// several collections, and being in none is normal.
public struct PhotoCollection: Identifiable, Codable, Sendable, Hashable {

    public let id: UUID
    public var name: String
    /// Ordered, and unique. Order is the import order until something reorders it.
    public private(set) var memberIDs: [ContentHash]
    public var settings: SheetSettings
    /// Which photographs are held in which cells. Must survive a quit.
    public var pins: [Pin]

    public init(
        id: UUID = UUID(),
        name: String,
        memberIDs: [ContentHash] = [],
        settings: SheetSettings = SheetSettings(),
        pins: [Pin] = []
    ) {
        self.id = id
        self.name = name
        self.memberIDs = []
        self.settings = settings
        self.pins = pins
        add(memberIDs)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, memberIDs, settings, pins
    }

    /// Defaulted, for the same reason `SheetSettings` is: `pins` did not exist
    /// when the first libraries were written.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        memberIDs = try container.decodeIfPresent([ContentHash].self, forKey: .memberIDs) ?? []
        settings = try container.decodeIfPresent(SheetSettings.self, forKey: .settings) ?? SheetSettings()
        pins = try container.decodeIfPresent([Pin].self, forKey: .pins) ?? []
    }

    @discardableResult
    public mutating func add(_ ids: [ContentHash]) -> Int {
        let existing = Set(memberIDs)
        var seen = existing
        var added = 0
        for id in ids where !seen.contains(id) {
            memberIDs.append(id)
            seen.insert(id)
            added += 1
        }
        return added
    }

    /// Puts a photograph back where it was. Membership is ordered, so appending
    /// it would be a different collection from the one that was there.
    public mutating func insert(_ id: ContentHash, at index: Int) {
        guard !memberIDs.contains(id) else { return }
        memberIDs.insert(id, at: min(max(index, 0), memberIDs.count))
    }

    public mutating func restore(_ restored: [Pin]) {
        for pin in restored where !pins.contains(pin) { pins.append(pin) }
    }

    public mutating func remove(_ ids: Set<ContentHash>) {
        memberIDs.removeAll { ids.contains($0) }
        pins.removeAll { ids.contains($0.photo) }
    }
}
