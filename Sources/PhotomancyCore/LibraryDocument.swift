import Foundation

/// Everything the library knows, as plain values. No file handles, no
/// observation, no main actor — so the rules about identity, de-duplication and
/// collection membership can be tested directly.
public struct LibraryDocument: Codable, Sendable, Equatable {

    public static let currentVersion = 1

    public var version: Int
    /// Unique by content hash, in import order.
    public private(set) var references: [PhotoReference]
    public var collections: [PhotoCollection]
    /// Settings for the All Photos view, which is virtual and so has nowhere
    /// else to keep them.
    public var allPhotosSettings: SheetSettings
    /// Likewise its pins.
    public var allPhotosPins: [Pin]
    /// Reopened on the next launch. `nil` is All Photos, which is also the
    /// first-launch view, so an absent value needs no special case.
    public var lastOpenedCollection: UUID?

    public init(
        version: Int = LibraryDocument.currentVersion,
        references: [PhotoReference] = [],
        collections: [PhotoCollection] = [],
        allPhotosSettings: SheetSettings = SheetSettings(),
        allPhotosPins: [Pin] = [],
        lastOpenedCollection: UUID? = nil
    ) {
        self.version = version
        self.references = []
        self.collections = collections
        self.allPhotosSettings = allPhotosSettings
        self.allPhotosPins = allPhotosPins
        self.lastOpenedCollection = lastOpenedCollection
        for reference in references { _ = insert(reference) }
    }

    enum CodingKeys: String, CodingKey {
        case version, references, collections, allPhotosSettings, allPhotosPins, lastOpenedCollection
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        references = try container.decodeIfPresent([PhotoReference].self, forKey: .references) ?? []
        collections = try container.decodeIfPresent([PhotoCollection].self, forKey: .collections) ?? []
        allPhotosSettings = try container.decodeIfPresent(SheetSettings.self, forKey: .allPhotosSettings) ?? SheetSettings()
        allPhotosPins = try container.decodeIfPresent([Pin].self, forKey: .allPhotosPins) ?? []
        lastOpenedCollection = try container.decodeIfPresent(UUID.self, forKey: .lastOpenedCollection)
    }

    // MARK: - References

    private var index: [ContentHash: Int] {
        var map: [ContentHash: Int] = [:]
        map.reserveCapacity(references.count)
        for (offset, reference) in references.enumerated() { map[reference.id] = offset }
        return map
    }

    public func reference(for id: ContentHash) -> PhotoReference? {
        references.first { $0.id == id }
    }

    /// Returns false when this photograph is already in the library — the same
    /// bytes imported twice from two paths are one photograph, which is what
    /// makes All Photos de-duplicate.
    @discardableResult
    public mutating func insert(_ reference: PhotoReference) -> Bool {
        guard !references.contains(where: { $0.id == reference.id }) else { return false }
        references.append(reference)
        return true
    }

    public mutating func updateBookmark(for id: ContentHash, to data: Data) {
        guard let offset = references.firstIndex(where: { $0.id == id }) else { return }
        references[offset] = references[offset].replacingBookmark(with: data)
    }

    public mutating func remove(_ ids: Set<ContentHash>) {
        references.removeAll { ids.contains($0.id) }
        allPhotosPins.removeAll { ids.contains($0.photo) }
        for offset in collections.indices { collections[offset].remove(ids) }
    }

    // MARK: - Pins

    /// `nil` is All Photos, which keeps its own pins like any other collection.
    public func pins(in collectionID: UUID?) -> [Pin] {
        guard let collectionID else { return allPhotosPins }
        return collections.first(where: { $0.id == collectionID })?.pins ?? []
    }

    public mutating func updatePins(_ pins: [Pin], for collectionID: UUID?) {
        guard let collectionID else {
            allPhotosPins = pins
            return
        }
        guard let offset = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[offset].pins = pins
    }

    /// The cell shape actually used to lay this collection out.
    public func cellAspect(for collectionID: UUID?) -> Double {
        settings(for: collectionID).cellShape.aspect(for: photos(in: collectionID))
    }

    // MARK: - Views

    /// The virtual collection: every reference, once. The widest pool chance can
    /// draw from, and the first-launch view before any collection exists.
    public var allPhotos: [PhotoReference] {
        references
    }

    /// `nil` means All Photos.
    public func photos(in collectionID: UUID?) -> [PhotoReference] {
        guard let collectionID else { return allPhotos }
        guard let collection = collections.first(where: { $0.id == collectionID }) else { return [] }
        let map = index
        return collection.memberIDs.compactMap { id in map[id].map { references[$0] } }
    }

    public func settings(for collectionID: UUID?) -> SheetSettings {
        guard let collectionID else { return allPhotosSettings }
        return collections.first(where: { $0.id == collectionID })?.settings ?? SheetSettings()
    }

    public mutating func updateSettings(_ settings: SheetSettings, for collectionID: UUID?) {
        guard let collectionID else {
            allPhotosSettings = settings
            return
        }
        guard let offset = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[offset].settings = settings
    }

    // MARK: - Collections

    @discardableResult
    public mutating func addCollection(named name: String) -> PhotoCollection {
        let collection = PhotoCollection(name: name)
        collections.append(collection)
        return collection
    }

    public mutating func removeCollection(_ id: UUID) {
        collections.removeAll { $0.id == id }
        if lastOpenedCollection == id { lastOpenedCollection = nil }
    }

    /// Adding to All Photos (`nil`) is a no-op beyond the reference already
    /// existing — every reference is in All Photos by definition.
    public mutating func add(_ ids: [ContentHash], to collectionID: UUID?) {
        guard let collectionID,
              let offset = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[offset].add(ids)
    }
}
