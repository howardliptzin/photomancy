import Foundation

/// Everything the library knows, as plain values. No file handles, no
/// observation, no main actor — so the rules about identity, de-duplication and
/// collection membership can be tested directly.
public struct LibraryDocument: Codable, Sendable, Equatable {

    public static let currentVersion = 1

    public var version: Int
    /// Unique by content hash, in import order.
    public private(set) var references: [PhotoReference]
    /// Read-only from outside: membership changes only through the methods here,
    /// which keep the library equal to the union of the collections.
    public private(set) var collections: [PhotoCollection]
    /// Settings for the All Photos view, which is not a stored collection and so has nowhere
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
    ///
    /// Not public. On its own it would put a photograph in the library outside
    /// any collection, which All Photos — the union of the collections — forbids.
    /// The app's only way in is `add(_:to:)` with references.
    mutating func insert(_ reference: PhotoReference) -> Bool {
        guard !references.contains(where: { $0.id == reference.id }) else { return false }
        references.append(reference)
        return true
    }

    /// The one public way into the library: into a named collection. Returns how
    /// many photographs were new to the library. One already there still joins
    /// this collection; with no such collection, nothing is added at all.
    @discardableResult
    public mutating func add(_ references: [PhotoReference], to collectionID: UUID) -> Int {
        guard collections.contains(where: { $0.id == collectionID }) else { return 0 }
        var added = 0
        for reference in references where insert(reference) { added += 1 }
        add(references.map(\.id), to: collectionID)
        return added
    }

    public mutating func renameCollection(_ id: UUID, to name: String) {
        guard let offset = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[offset].name = name
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

    // MARK: - Moving

    /// Moves photographs from one sheet into another collection, as one change.
    ///
    /// One change rather than a removal and then an add: removing first would,
    /// for a moment, take a photograph whose only collection is the source out of
    /// the library, and its All Photos pins with it. Here the photographs join
    /// the destination before they leave the source, so nothing ever departs.
    ///
    /// `photographs` are in sheet cell order and join the destination in that
    /// order. Those in `pinned` stay pinned: they fill the destination's first
    /// cells not already pinned there, in the same order, so a sequence found on
    /// one sheet carries across. A photograph already pinned in the destination
    /// keeps the cell it has there.
    ///
    /// From All Photos (`source == nil`) nothing is removed — there is no
    /// collection to take the photographs out of — so it adds.
    ///
    /// Returns `nil` when nothing would change, so a no-op never lands in the
    /// undo history.
    public mutating func move(
        _ photographs: [ContentHash],
        pinned: Set<ContentHash>,
        from source: UUID?,
        to destination: UUID
    ) -> Transfer? {
        guard source != destination,
              let target = collections.firstIndex(where: { $0.id == destination })
        else { return nil }

        let available: Set<ContentHash>
        if let source {
            guard let collection = collections.first(where: { $0.id == source }) else { return nil }
            available = Set(collection.memberIDs)
        } else {
            available = Set(references.map(\.id))
        }
        var seen: Set<ContentHash> = []
        let moving = photographs.filter { available.contains($0) && seen.insert($0).inserted }
        guard !moving.isEmpty else { return nil }

        let members = Set(collections[target].memberIDs)
        let joined = moving.filter { !members.contains($0) }
        collections[target].add(joined)

        let alreadyPinned = Set(collections[target].pins.map(\.photo))
        var taken = Set(collections[target].pins.map(\.cell))
        var cell = 0
        var placed: [Pin] = []
        for photo in moving where pinned.contains(photo) && !alreadyPinned.contains(photo) {
            while taken.contains(cell) { cell += 1 }
            placed.append(Pin(photo: photo, cell: cell))
            taken.insert(cell)
        }
        collections[target].pins.append(contentsOf: placed)

        // Only now out of the source: every one of them is in the destination,
        // so none can leave the library.
        let removal = source.flatMap { removeFromCollection(Set(moving), collectionID: $0) }
        assert(removal?.departures.isEmpty ?? true, "a move never takes a photograph out of the library")

        guard removal != nil || !joined.isEmpty || !placed.isEmpty else { return nil }
        return Transfer(
            source: source,
            destination: destination,
            photographs: moving,
            pinned: moving.filter { pinned.contains($0) },
            removal: removal,
            joined: joined,
            pins: placed
        )
    }

    /// Takes a move back: the photographs return to the source at their indices
    /// with their pins, and leave the destination if the move put them there.
    /// A collection the move created stays, empty.
    public mutating func reverse(_ transfer: Transfer) {
        if let removal = transfer.removal { restore(removal) }
        guard let target = collections.firstIndex(where: { $0.id == transfer.destination }) else { return }
        // Back in the source first, so these are held elsewhere by now. Checked
        // anyway: leaving a photograph in the destination is a partial undo,
        // taking it out of its last collection would break the union.
        let elsewhere = Set(collections.filter { $0.id != transfer.destination }.flatMap(\.memberIDs))
        collections[target].remove(Set(transfer.joined).intersection(elsewhere))
        collections[target].pins.removeAll { transfer.pins.contains($0) }
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
    /// its last one — and nothing outside this type can do either another way.
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

// MARK: - Relink

extension LibraryDocument {

    /// Every photograph the library holds that cannot be read right now.
    ///
    /// A `stat` each through the resolver, so it costs milliseconds even on a
    /// large library and can be asked whenever it might have changed.
    public func missingPhotographs(resolver: BookmarkResolver) -> [Relink.Missing] {
        references.compactMap { reference in
            do {
                try resolver.withAccess(reference) { _ in }
                return nil
            } catch PhotoAccessError.missing, PhotoAccessError.unresolvable {
                // Both are repaired by pointing the photograph at the file
                // again: one has lost its target, the other its token.
                return Relink.Missing(
                    id: reference.id,
                    displayName: reference.displayName,
                    fileSize: reference.fileSize
                )
            } catch {
                return nil
            }
        }
    }

    /// Point a photograph at a file the person chose, if it really is that
    /// photograph.
    ///
    /// **One change, and every collection recovers.** A reference lives once in
    /// the library and collections hold ids, so a relinked photograph is fixed
    /// everywhere at once — in each collection that holds it and in All Photos —
    /// without touching membership, pins, or anything else.
    ///
    /// Not undoable, and does not need to be: it replaces a token that no longer
    /// works with one that does. Nothing is lost to put back.
    @discardableResult
    public mutating func relink(_ id: ContentHash, to url: URL) throws -> PhotoReference {
        guard let offset = references.firstIndex(where: { $0.id == id }) else {
            throw Relink.Failure.notInLibrary
        }
        let existing = references[offset]

        let hash: ContentHash
        do {
            hash = try ContentHasher.hash(contentsOf: url)
        } catch {
            throw Relink.Failure.unreadable(name: url.lastPathComponent, underlying: error)
        }
        guard hash == id else {
            throw Relink.Failure.differentPhotograph(
                chosen: url.lastPathComponent, expected: existing.displayName
            )
        }

        let bookmark = try Relink.bookmark(for: url)
        // The name follows the file. It is for display and for finding the
        // photograph again, never for identity, so a file renamed while it was
        // away should show under the name it has now.
        references[offset] = existing.relinked(to: url.lastPathComponent, bookmark: bookmark)
        return references[offset]
    }
}
