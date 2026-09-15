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

/// Photographs moved from one sheet into another collection, and everything
/// needed to take the move back.
///
/// Nothing leaves the library in a move — the photographs join the destination
/// before they leave the source — so no `PhotoReference` travels here: ids,
/// indices and pins, about a hundred bytes a photograph.
public struct Transfer: Equatable, Sendable {

    /// `nil` is All Photos, which holds nothing of its own: from there the
    /// photographs are added and nothing is removed.
    public let source: UUID?
    public let destination: UUID
    /// What was asked for, in sheet cell order, so redo can ask again.
    public let photographs: [ContentHash]
    /// Of those, the ones pinned on the source sheet, in the same order.
    public let pinned: [ContentHash]
    /// Where they sat in the source and the pins that went with them. `nil`
    /// from All Photos. Never carries departures.
    public let removal: Restoration?
    /// Photographs that were not already in the destination, and so leave it
    /// again on undo.
    public let joined: [ContentHash]
    /// Pins the move placed in the destination.
    public let pins: [Pin]

    public init(
        source: UUID?,
        destination: UUID,
        photographs: [ContentHash],
        pinned: [ContentHash],
        removal: Restoration?,
        joined: [ContentHash],
        pins: [Pin]
    ) {
        self.source = source
        self.destination = destination
        self.photographs = photographs
        self.pinned = pinned
        self.removal = removal
        self.joined = joined
        self.pins = pins
    }
}

/// One entry in the undo history: the sheet as it was left, what to call the
/// step, and — for a removal or a move — what it changed in the library.
public struct Step: Equatable, Sendable {

    public var arrangement: Arrangement
    /// Names the step in the Edit menu: "Undo Randomize", "Undo Remove".
    public var label: String
    /// Non-nil only for a removal from a collection. Everything else changes the
    /// arrangement alone, and restoring the previous arrangement is the whole
    /// inverse.
    public var restoration: Restoration?
    /// Non-nil only for a move to another collection.
    public var transfer: Transfer?

    public init(
        arrangement: Arrangement,
        label: String,
        restoration: Restoration? = nil,
        transfer: Transfer? = nil
    ) {
        self.arrangement = arrangement
        self.label = label
        self.restoration = restoration
        self.transfer = transfer
    }

    /// What the ten-removal bound counts. A move is not one: it carries no
    /// reference, so it costs what an ordinary step costs.
    public var isRemoval: Bool { restoration != nil }
}
