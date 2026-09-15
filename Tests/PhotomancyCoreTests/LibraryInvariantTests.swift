import XCTest
@testable import PhotomancyCore

/// All Photos is the union of the collections. The library keeps that by
/// construction rather than by repair, so it is tested the way a rule should be:
/// long random runs of everything that can change the library, checked after
/// every single step.
final class LibraryInvariantTests: XCTestCase {

    private let pool: [PhotoReference] = (0..<30).map { n in
        PhotoReference(
            id: ContentHasher.hash(Data("pool-\(n)".utf8)),
            displayName: "p\(n).jpg",
            fileSize: 1,
            pixelWidth: 3000,
            pixelHeight: 2000,
            bookmark: Data("\(n)".utf8)
        )
    }

    func testTheLibraryIsAlwaysTheUnionOfItsCollections() {
        for seed in UInt64(1)...25 {
            var rng = SeededGenerator(seed: seed)
            var document = LibraryDocument()
            // Removal steps, as the app's history holds them. Deleting a
            // collection or deleting from the library is not undoable and clears
            // them, exactly as the app does.
            var undo: [Restoration] = []
            var redo: [Restoration] = []

            for step in 0..<400 {
                let action = Int.random(in: 0..<8, using: &rng)
                let collections = document.collections.map(\.id)

                switch action {
                case 0 where collections.count < 6:
                    document.addCollection(named: "c\(step)")
                case 1 where !collections.isEmpty:
                    let count = Int.random(in: 1...5, using: &rng)
                    let batch = (0..<count).map { _ in pool.randomElement(using: &rng)! }
                    document.add(batch, to: collections.randomElement(using: &rng)!)
                case 2 where !collections.isEmpty && !document.references.isEmpty:
                    let ids = Array(document.references.map(\.id).shuffled(using: &rng).prefix(3))
                    document.add(ids, to: collections.randomElement(using: &rng)!)
                case 3:
                    guard let collection = document.collections
                        .filter({ !$0.memberIDs.isEmpty })
                        .randomElement(using: &rng) else { break }
                    let count = Int.random(in: 1...3, using: &rng)
                    let ids = Set(collection.memberIDs.shuffled(using: &rng).prefix(count))
                    if let restoration = document.removeFromCollection(ids, collectionID: collection.id) {
                        undo.append(restoration)
                        redo.removeAll()
                    }
                case 4:
                    guard let restoration = undo.popLast() else { break }
                    document.restore(restoration)
                    redo.append(restoration)
                case 5:
                    // As the app redoes: remove again, keep the original step.
                    guard let restoration = redo.popLast() else { break }
                    _ = document.removeFromCollection(
                        Set(restoration.memberships.map(\.photo)),
                        collectionID: restoration.collection
                    )
                    undo.append(restoration)
                case 6 where !collections.isEmpty:
                    document.removeCollection(collections.randomElement(using: &rng)!)
                    undo.removeAll()
                    redo.removeAll()
                case 7 where !document.references.isEmpty:
                    document.remove(Set(document.references.map(\.id).shuffled(using: &rng).prefix(2)))
                    undo.removeAll()
                    redo.removeAll()
                default:
                    break
                }

                let library = Set(document.references.map(\.id))
                let union = Set(document.collections.flatMap(\.memberIDs))
                XCTAssertEqual(library, union, "seed \(seed), step \(step), action \(action)")
                guard library == union else { return }
            }
        }
    }
}
