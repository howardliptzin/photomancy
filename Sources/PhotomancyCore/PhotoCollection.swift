import Foundation

/// How a sheet is set up. Persisted per collection, including for All Photos,
/// which carries its own settings and its own pins like any other collection.
public struct SheetSettings: Codable, Sendable, Hashable {

    /// The shape of a cell, chosen per collection.
    ///
    /// Square is the default because it is the only shape where a photograph and
    /// its transpose occupy the same area, and because it is the minimax choice:
    /// it does not make any photograph biggest, it makes the worst-placed one
    /// least bad. With random placement the worst case is a recurring event
    /// rather than an edge case, which is what makes that the right objective
    /// here and not in an ordinary layout tool.
    public enum CellShape: String, Codable, Sendable, Hashable, CaseIterable {
        case square
        case threeByTwo
        case fourByThree
        /// The cell takes the proportions of the sheet it prints on.
        case matchPage
        /// The most common ratio in the collection.
        ///
        /// Offered, never a default: it would change the shape of a sheet on
        /// import, with nothing on screen to say why, and All Photos drifts as
        /// the whole library grows.
        case derivedFromCollection
    }


    public enum CellMode: String, Codable, Sendable {
        /// The whole frame is shown, background around it. The default, and
        /// settled: Fill centre-crops, v1 has no crop control, and so that crop
        /// cannot be corrected. It is also a decision the tool made rather than
        /// the photographer or chance, which is the one thing this instrument
        /// is not supposed to do.
        case fit
        /// An even mosaic, at the cost of a crop nobody can adjust in v1.
        case fill
    }

    public var columns: Int
    public var rows: Int
    /// Pixels on screen, converted for print at the chosen resolution.
    public var gap: Double
    public var backgroundHex: String
    public var cellMode: CellMode
    public var cellShape: CellShape
    /// The sheet itself. `CellShape.matchPage` resolves against this.
    public var paper: Paper

    public init(
        columns: Int = 5,
        rows: Int = 4,
        gap: Double = 12,
        backgroundHex: String = "#FFFFFF",
        cellMode: CellMode = .fit,
        cellShape: CellShape = .square,
        paper: Paper = Paper()
    ) {
        self.columns = columns
        self.rows = rows
        self.gap = gap
        self.backgroundHex = backgroundHex
        self.cellMode = cellMode
        self.cellShape = cellShape
        self.paper = paper
    }

    enum CodingKeys: String, CodingKey {
        case columns, rows, gap, backgroundHex, cellMode, cellShape, paper
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
        cellMode = try container.decodeIfPresent(CellMode.self, forKey: .cellMode) ?? fallback.cellMode
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

    public init(
        id: UUID = UUID(),
        name: String,
        memberIDs: [ContentHash] = [],
        settings: SheetSettings = SheetSettings()
    ) {
        self.id = id
        self.name = name
        self.memberIDs = []
        self.settings = settings
        add(memberIDs)
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

    public mutating func remove(_ ids: Set<ContentHash>) {
        memberIDs.removeAll { ids.contains($0) }
    }
}
