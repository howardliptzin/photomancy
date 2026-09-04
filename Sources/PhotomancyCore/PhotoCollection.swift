import Foundation

/// How a sheet is set up. Persisted per collection, including for All Photos,
/// which carries its own settings and its own pins like any other collection.
public struct SheetSettings: Codable, Sendable, Hashable {

    public enum CellMode: String, Codable, Sendable {
        /// The whole frame is shown, background around it. The brief's default:
        /// a layout tool has no business cropping a photographer's edges.
        case fit
        /// An even mosaic, at the cost of a crop.
        case fill
    }

    public var columns: Int
    public var rows: Int
    /// Pixels on screen, converted for print at the chosen resolution.
    public var gap: Double
    public var backgroundHex: String
    public var cellMode: CellMode

    public init(
        columns: Int = 5,
        rows: Int = 4,
        gap: Double = 12,
        backgroundHex: String = "#FFFFFF",
        cellMode: CellMode = .fit
    ) {
        self.columns = columns
        self.rows = rows
        self.gap = gap
        self.backgroundHex = backgroundHex
        self.cellMode = cellMode
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
