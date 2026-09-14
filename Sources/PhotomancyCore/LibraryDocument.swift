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

    /// Takes photographs out of one collection and returns everything needed to
    /// put them back. The reference itself is untouched — it is still in the
    /// library and still in every other collection.
    ///
    /// Returns `nil` when nothing was actually removed, so a no-op never lands
    /// in the undo history as a step that appears to do something.
    public mutating func removeFromCollection(
        _ ids: Set<ContentHash>,
        collectionID: UUID
    ) -> Restoration? {
        guard let offset = collections.firstIndex(where: { $0.id == collectionID }) else { return nil }

        let memberships = collections[offset].memberIDs.enumerated()
            .filter { ids.contains($0.element) }
            .map { Restoration.Membership(photo: $0.element, index: $0.offset) }
        guard !memberships.isEmpty else { return nil }

        let pins = collections[offset].pins.filter { ids.contains($0.photo) }
        collections[offset].remove(ids)

        // All Photos is the union of the collections, so a photograph that was
        // only in this one leaves the library with it.
        let departing = unfiled(among: Set(memberships.map(\.photo)))
        let departures = references.enumerated()
            .filter { departing.contains($0.element.id) }
            .map { Restoration.Departure(reference: $0.element, index: $0.offset) }
        let allPhotosPins = self.allPhotosPins.filter { departing.contains($0.photo) }
        references.removeAll { departing.contains($0.id) }
        self.allPhotosPins.removeAll { departing.contains($0.photo) }

        return Restoration(
            collection: collectionID,
            memberships: memberships,
            pins: pins,
            departures: departures,
            allPhotosPins: allPhotosPins
        )
    }

    public mutating func restore(_ restoration: Restoration) {
        guard let offset = collections.firstIndex(where: { $0.id == restoration.collection }) else { return }
        // Back into the library first, each where it sat, ascending so each index
        // is right by the time it is used.
        for departure in restoration.departures.sorted(by: { $0.index < $1.index })
        where !references.contains(where: { $0.id == departure.reference.id }) {
            references.insert(departure.reference, at: min(max(departure.index, 0), references.count))
        }
        for pin in restoration.allPhotosPins where !allPhotosPins.contains(pin) {
            allPhotosPins.append(pin)
        }
        // Ascending, so each index is correct by the time it is used.
        for membership in restoration.memberships.sorted(by: { $0.index < $1.index }) {
            collections[offset].insert(membership.photo, at: membership.index)
        }
        collections[offset].restore(restoration.pins)
    }

    /// `nil` means All Photos, the union of the collections — so removing there
    /// is removing from the library. Removing from a collection takes the
    /// photograph out of that list, and out of the library only if it was in no
    /// other.
    public mutating func remove(_ ids: Set<ContentHash>, from collectionID: UUID?) {
        guard let collectionID else {
            remove(ids)
            return
        }
        _ = removeFromCollection(ids, collectionID: collectionID)
    }

    /// Of these photographs, the ones no collection holds.
    private func unfiled(among ids: Set<ContentHash>) -> Set<ContentHash> {
        guard !ids.isEmpty else { return [] }
        return ids.subtracting(collections.flatMap(\.memberIDs))
    }

    /// Puts every photograph that is in no collection into one named `name`, and
    /// returns how many.
    ///
    /// All Photos is the union of the collections. A library written before that
    /// rule can hold photographs imported straight into All Photos, which would
    /// otherwise vanish from view with nothing lost on disk and no way to reach
    /// them. Runs on every load, so it also repairs anything that ever slips
    /// through. An existing collection of that name is added to, not duplicated.
    @discardableResult
    public mutating func gatherUnfiled(into name: String = "Unfiled") -> Int {
        let members = Set(collections.flatMap(\.memberIDs))
        let loose = references.map(\.id).filter { !members.contains($0) }
        guard !loose.isEmpty else { return 0 }
        if let offset = collections.firstIndex(where: { $0.name == name }) {
            collections[offset].add(loose)
        } else {
            collections.append(PhotoCollection(name: name, memberIDs: loose))
        }
        return loose.count
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

    /// The union of the collections: every photograph in any of them, once. The
    /// widest pool chance can draw from.
    ///
    /// Read straight from `references` because the two are kept equal by rule: a
    /// photograph enters the library only into a collection, and leaves it with
    /// its last one. `gatherUnfiled()` repairs a library written before that rule.
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

    /// Photographs in no other collection leave the library with it — All Photos
    /// is the union of the collections. Returns the ones that left.
    @discardableResult
    public mutating func removeCollection(_ id: UUID) -> Set<ContentHash> {
        let members = collections.first(where: { $0.id == id })?.memberIDs ?? []
        collections.removeAll { $0.id == id }
        if lastOpenedCollection == id { lastOpenedCollection = nil }
        let departing = unfiled(among: Set(members))
        references.removeAll { departing.contains($0.id) }
        allPhotosPins.removeAll { departing.contains($0.photo) }
        return departing
    }

    /// Always into a named collection. All Photos holds nothing of its own, so
    /// there is no adding to it.
    public mutating func add(_ ids: [ContentHash], to collectionID: UUID) {
        guard let offset = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[offset].add(ids)
    }
}
