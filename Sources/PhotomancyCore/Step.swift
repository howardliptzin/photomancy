import Foundation

/// What was taken out of a collection, and everything needed to put it back.
///
/// Only membership is restored, because only membership was removed —
/// "Remove from Collection" never touches the reference itself. That makes the
/// inverse cheap: identities, positions and pins, on the order of a hundred
/// bytes a photograph, against the ~940-byte bookmark that would be needed to
/// restore a reference deleted from the library.
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

    public let collection: UUID
    public let memberships: [Membership]
    /// Pins that referred to those photographs and went with them.
    public let pins: [Pin]

    public init(collection: UUID, memberships: [Membership], pins: [Pin]) {
        self.collection = collection
        self.memberships = memberships
        self.pins = pins
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
