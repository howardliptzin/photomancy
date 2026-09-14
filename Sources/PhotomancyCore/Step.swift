import Foundation

/// What was taken out of a collection, and everything needed to put it back.
///
/// Usually only membership is restored, because usually only membership was
/// removed: identities, positions and pins, on the order of a hundred bytes a
/// photograph. The exception is a photograph that was in no other collection —
/// All Photos is the union of the collections, so it left the library as well,
/// and its reference (with its ~940-byte bookmark) travels here too.
public struct Restoration: Equatable, Sendable {

    /// Where a photograph sat in the collection's ordered membership. The order
    /// is meaningful, so putting the photograph back at the end would be a
    /// different collection from the one that was there before.
    public struct Membership: Equatable, Sendable {
        public let photo: ContentHash
        public let index: Int
        public init(photo: ContentHash, index: Int) {
            self.photo = photo
            self.index = index
        }
    }

    /// A photograph that left the library along with its last collection, and
    /// where it sat in the library's order.
    public struct Departure: Equatable, Sendable {
        public let reference: PhotoReference
        public let index: Int
        public init(reference: PhotoReference, index: Int) {
            self.reference = reference
            self.index = index
        }
    }

    public let collection: UUID
    public let memberships: [Membership]
    /// Pins that referred to those photographs and went with them.
    public let pins: [Pin]
    /// Photographs this was the last collection for. All Photos is the union of
    /// the collections, so they left the library too — carried here, bookmark
    /// and all, so undo still puts them back. Bounded by the ten reversible
    /// removals.
    public let departures: [Departure]
    /// All Photos pins on those departed photographs.
    public let allPhotosPins: [Pin]

    public init(
        collection: UUID,
        memberships: [Membership],
        pins: [Pin],
        departures: [Departure] = [],
        allPhotosPins: [Pin] = []
    ) {
        self.collection = collection
        self.memberships = memberships
        self.pins = pins
        self.departures = departures
        self.allPhotosPins = allPhotosPins
    }
}

/// One entry in the undo history: the sheet as it was left, what to call the
/// step, and — for a removal — what it took away.
public struct Step: Equatable, Sendable {

    public var arrangement: Arrangement
    /// Names the step in the Edit menu: "Undo Randomize", "Undo Remove".
    public var label: String
    /// Non-nil only for a removal from a collection. Everything else changes the
    /// arrangement alone, and restoring the previous arrangement is the whole
    /// inverse.
    public var restoration: Restoration?

    public init(arrangement: Arrangement, label: String, restoration: Restoration? = nil) {
        self.arrangement = arrangement
        self.label = label
        self.restoration = restoration
    }

    public var isRemoval: Bool { restoration != nil }
}
