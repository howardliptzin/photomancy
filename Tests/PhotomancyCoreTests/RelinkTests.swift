import XCTest
import UniformTypeIdentifiers
@testable import PhotomancyCore

/// Real files, really moved. The whole point of a relink is that the path it
/// was imported from no longer works, and a fixture that never moves cannot
/// show that.
@MainActor
final class RelinkTests: XCTestCase {

    private var directory: URL!
    private var elsewhere: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        directory = try TestImages.temporaryDirectory()
        elsewhere = directory.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        store = LibraryStore(fileURL: directory.appendingPathComponent("library.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Distinct content per photograph, or two fixtures are one photograph and
    /// the resolver's cache answers for both.
    private var written = 0

    @discardableResult
    private func write(_ name: String, in folder: URL? = nil, width: Int = 900, height: Int = 600) throws -> URL {
        written += 1
        let image = try TestImages.makeCGImage(width: width + written, height: height)
        return try TestImages.write(image, as: .jpeg,
                                    to: (folder ?? directory).appendingPathComponent(name))
    }

    private func imported(_ name: String) throws -> PhotoReference {
        let reference = try Importer.makeReference(for: try write(name))
        let collection = store.addCollection(named: "Work")
        _ = store.add([reference], to: collection.id)
        return reference
    }

    /// Break the link to a file, leaving an identical copy somewhere else.
    ///
    /// Copy-then-delete, deliberately not `moveItem`. **A move on the same
    /// volume does not break a bookmark**: bookmarks resolve by file ID, so the
    /// file is found at its new path, reported stale, and `BookmarkResolver`
    /// re-creates and re-saves it. Measured 2026-09-22, and it means a
    /// photograph dragged to another folder in the Finder never goes missing.
    ///
    /// What does break is the file being *replaced* rather than moved — a new
    /// inode with the same contents. Deleted and restored from a backup, synced
    /// down by Dropbox or iCloud, re-downloaded, copied to another volume, or
    /// exported over the top. Relink is a recovery from that, and a test that
    /// only moved files would have been testing a path the app already handles
    /// on its own.
    @discardableResult
    private func displace(_ name: String, to folder: URL) throws -> URL {
        let origin = directory.appendingPathComponent(name)
        let destination = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: origin, to: destination)
        try FileManager.default.removeItem(at: origin)
        return destination
    }

    /// Gone, with no copy anywhere.
    private func destroy(_ name: String) throws {
        try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    // MARK: - Missing

    func testAMovedPhotographIsReportedMissingAndTheRestAreNot() throws {
        let gone = try imported("gone.jpg")
        let here = try imported("here.jpg")
        _ = try displace("gone.jpg", to: elsewhere)

        let missing = store.missingPhotographs()
        XCTAssertEqual(missing.map(\.id), [gone.id])
        XCTAssertEqual(missing.first?.displayName, "gone.jpg")
        XCTAssertEqual(missing.first?.fileSize, gone.fileSize)
        XCTAssertFalse(missing.contains { $0.id == here.id })
    }

    func testNothingIsMissingWhenEverythingIsWhereItWas() throws {
        _ = try imported("a.jpg")
        _ = try imported("b.jpg")
        XCTAssertTrue(store.missingPhotographs().isEmpty)
    }

    // MARK: - Relinking one photograph

    func testRelinkingAMovedPhotographMakesItReadableAgain() throws {
        let reference = try imported("frame.jpg")
        let moved = try displace("frame.jpg", to: elsewhere)
        XCTAssertThrowsError(try store.resolver.withAccess(reference) { _ in },
                             "the fixture must really be unreadable first — see displace()")

        try store.relink(reference.id, to: moved)

        XCTAssertTrue(store.missingPhotographs().isEmpty)
        let updated = try XCTUnwrap(store.document.reference(for: reference.id))
        let pixels = try store.resolver.withAccess(updated) { url in
            try ThumbnailDecoder.probe(url: url)
        }
        XCTAssertEqual(pixels.width, reference.pixelWidth, "and it is the same photograph")
    }

    /// The reason this goes through the store. A resolution is cached for the
    /// life of the process, so without forgetting it the app keeps reading
    /// through the path that no longer works.
    func testTheResolverForgetsThePathItCachedBeforeTheMove() throws {
        let reference = try imported("cached.jpg")
        // Resolve once while it is still there, to fill the cache.
        _ = try store.resolver.withAccess(reference) { $0 }
        let moved = try displace("cached.jpg", to: elsewhere)

        try store.relink(reference.id, to: moved)

        let updated = try XCTUnwrap(store.document.reference(for: reference.id))
        let path = try store.resolver.withAccess(updated) { $0.path }
        XCTAssertTrue(path.contains("moved"), "reading through the new location, not the cached old one")
    }

    func testTheIdIsUnchangedSoNothingElseInTheLibraryMoves() throws {
        let reference = try imported("stable.jpg")
        let moved = try displace("stable.jpg", to: elsewhere)
        let before = store.document.collections.map(\.memberIDs)

        let after = try store.relink(reference.id, to: moved)

        XCTAssertEqual(after.id, reference.id, "identity is the content, and the content did not change")
        XCTAssertEqual(store.document.collections.map(\.memberIDs), before)
        XCTAssertEqual(after.fileSize, reference.fileSize)
        XCTAssertEqual(after.pixelWidth, reference.pixelWidth)
        XCTAssertEqual(after.addedAt, reference.addedAt)
    }

    /// One reference, held by id in every collection, so one change fixes all
    /// of them — and All Photos, which is their union.
    func testEveryCollectionHoldingItRecoversAtOnce() throws {
        let reference = try Importer.makeReference(for: try write("shared.jpg"))
        let first = store.addCollection(named: "One")
        let second = store.addCollection(named: "Two")
        _ = store.add([reference], to: first.id)
        _ = store.add([reference], to: second.id)
        let moved = try displace("shared.jpg", to: elsewhere)

        try store.relink(reference.id, to: moved)

        for collection in [first, second] {
            let photo = try XCTUnwrap(store.photos(in: collection.id).first)
            XCTAssertNoThrow(try store.resolver.withAccess(photo) { _ in }, collection.name)
        }
        let all = try XCTUnwrap(store.photos(in: nil).first)
        XCTAssertNoThrow(try store.resolver.withAccess(all) { _ in }, "All Photos")
    }

    /// The name is for display and for finding it again, never for identity,
    /// so a file renamed while it was away shows under the name it has now.
    func testTheNameFollowsTheFile() throws {
        let reference = try imported("old-name.jpg")
        let moved = try displace("old-name.jpg", to: elsewhere)
        let renamed = elsewhere.appendingPathComponent("new-name.jpg")
        try FileManager.default.moveItem(at: moved, to: renamed)

        let after = try store.relink(reference.id, to: renamed)
        XCTAssertEqual(after.displayName, "new-name.jpg")
        XCTAssertEqual(after.id, reference.id)
    }

    // MARK: - Strictly by content

    /// The one failure this must not have: quietly putting a different picture
    /// into a sequence the photographer already chose.
    func testADifferentPhotographIsRefused() throws {
        let reference = try imported("wanted.jpg")
        _ = try displace("wanted.jpg", to: elsewhere)
        let impostor = try write("impostor.jpg", in: elsewhere)

        XCTAssertThrowsError(try store.relink(reference.id, to: impostor)) { error in
            guard case Relink.Failure.differentPhotograph(let chosen, let expected) = error else {
                return XCTFail("expected differentPhotograph, got \(error)")
            }
            XCTAssertEqual(chosen, "impostor.jpg")
            XCTAssertEqual(expected, "wanted.jpg")
        }
        XCTAssertEqual(store.missingPhotographs().map(\.id), [reference.id], "still missing")
    }

    /// A re-exported edit is a different photograph — the settled answer, and
    /// the case most likely to be offered by mistake.
    func testAReExportedCopyOfTheSameFrameIsADifferentPhotograph() throws {
        let original = try write("frame.jpg", width: 1200, height: 800)
        let reference = try Importer.makeReference(for: original)
        let collection = store.addCollection(named: "Work")
        _ = store.add([reference], to: collection.id)

        // The same pixels, written again at another quality: a different file.
        let image = try TestImages.makeCGImage(width: 1200 + written, height: 800)
        let reExported = elsewhere.appendingPathComponent("frame.jpg")
        guard let destination = CGImageDestinationCreateWithURL(
            reExported as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw XCTSkip("cannot write JPEG") }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.5] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw XCTSkip("cannot finalise") }
        try FileManager.default.removeItem(at: original)

        XCTAssertThrowsError(try store.relink(reference.id, to: reExported)) { error in
            guard case Relink.Failure.differentPhotograph = error else {
                return XCTFail("a re-export must not relink, got \(error)")
            }
        }
    }

    func testRelinkingSomethingNotInTheLibraryFails() throws {
        let stranger = try write("stranger.jpg")
        XCTAssertThrowsError(try store.relink(ContentHash(hex: String(repeating: "a", count: 64)), to: stranger)) { error in
            guard case Relink.Failure.notInLibrary = error else {
                return XCTFail("expected notInLibrary, got \(error)")
            }
        }
    }

    func testAFileThatCannotBeReadFailsRatherThanRelinking() throws {
        let reference = try imported("real.jpg")
        try destroy("real.jpg")
        let missingFile = elsewhere.appendingPathComponent("not-there.jpg")

        XCTAssertThrowsError(try store.relink(reference.id, to: missingFile)) { error in
            guard case Relink.Failure.unreadable = error else {
                return XCTFail("expected unreadable, got \(error)")
            }
        }
    }

    // MARK: - A whole folder

    func testAFolderRelinksEveryPhotographItHolds() throws {
        var references: [PhotoReference] = []
        for name in ["one.jpg", "two.jpg", "three.jpg"] {
            references.append(try imported(name))
        }
        let stayed = try imported("stayed.jpg")
        for name in ["one.jpg", "two.jpg", "three.jpg"] { _ = try displace(name, to: elsewhere) }
        XCTAssertEqual(store.missingPhotographs().count, 3)

        let result = store.relink(folderAt: elsewhere)

        XCTAssertEqual(result.relinked.count, 3)
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertTrue(store.missingPhotographs().isEmpty)
        XCTAssertNoThrow(try store.resolver.withAccess(
            try XCTUnwrap(store.document.reference(for: stayed.id))) { _ in },
            "the one that never moved is untouched")
    }

    func testAFolderRelinksWhatItCanAndLeavesTheRest() throws {
        let found = try imported("found.jpg")
        let lost = try imported("lost.jpg")
        _ = try displace("found.jpg", to: elsewhere)
        try destroy("lost.jpg")

        let result = store.relink(folderAt: elsewhere)

        XCTAssertEqual(result.relinked.map(\.id), [found.id])
        XCTAssertEqual(store.missingPhotographs().map(\.id), [lost.id])
    }

    func testAFolderWithNothingMatchingRelinksNothing() throws {
        let reference = try imported("wanted.jpg")
        try destroy("wanted.jpg")
        _ = try write("unrelated.jpg", in: elsewhere)

        let result = store.relink(folderAt: elsewhere)
        XCTAssertTrue(result.relinked.isEmpty)
        XCTAssertEqual(store.missingPhotographs().map(\.id), [reference.id])
    }

    // MARK: - Size before hash

    /// What makes a folder search affordable: identical content means identical
    /// length, so a size mismatch rules a candidate out with a `stat` rather
    /// than a full read.
    func testOnlyFilesOfExactlyTheRightSizeAreWorthHashing() {
        let missing = Relink.Missing(id: ContentHash(hex: String(repeating: "b", count: 64)),
                                     displayName: "x.jpg", fileSize: 4096)
        XCTAssertTrue(Relink.couldMatch(size: 4096, missing))
        XCTAssertFalse(Relink.couldMatch(size: 4095, missing))
        XCTAssertFalse(Relink.couldMatch(size: 4097, missing))

        let unknown = Relink.Missing(id: missing.id, displayName: "x.jpg", fileSize: 0)
        XCTAssertFalse(Relink.couldMatch(size: 0, unknown), "an unrecorded size matches nothing")
    }

    func testAFolderOfLargerFilesIsNotHashed() throws {
        let reference = try imported("small.jpg")
        try destroy("small.jpg")
        // Nothing here is the right size, so nothing here is hashed.
        for index in 0..<5 { _ = try write("big\(index).jpg", in: elsewhere, width: 3000, height: 2000) }

        XCTAssertTrue(Relink.search(folder: elsewhere, for: store.missingPhotographs()).isEmpty)
        XCTAssertEqual(store.missingPhotographs().map(\.id), [reference.id])
    }

    // MARK: - It survives being written down

    func testARelinkedPhotographIsStillRelinkedAfterTheLibraryIsReloaded() throws {
        let reference = try imported("persisted.jpg")
        let moved = try displace("persisted.jpg", to: elsewhere)
        try store.relink(reference.id, to: moved)

        let reopened = LibraryStore(fileURL: directory.appendingPathComponent("library.json"))
        reopened.load()
        let photo = try XCTUnwrap(reopened.document.reference(for: reference.id))
        XCTAssertEqual(photo.displayName, "persisted.jpg")
        XCTAssertNoThrow(try reopened.resolver.withAccess(photo) { _ in },
                         "the new bookmark was written, not just held in memory")
    }

    // MARK: - What a failed resolution actually means

    /// Measured in the running sandboxed app, not guessed: a bookmark whose
    /// target has been deleted resolves to Cocoa 259, the *corrupt file* code,
    /// and not to either no-such-file code. Classified as lost permission it
    /// left Relink… disabled in the one case it exists for.
    func testABookmarkWhoseTargetHasGoneIsMissingRatherThanLostPermission() {
        for code in [NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileReadCorruptFileError] {
            let error = NSError(domain: NSCocoaErrorDomain, code: code)
            guard case PhotoAccessError.missing = BookmarkResolver.resolutionFailure(error, name: "x.jpg") else {
                return XCTFail("Cocoa \(code) should read as missing")
            }
        }
    }

    func testAnUnrecognisedFailureIsStillReportedAsLostPermission() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: 1)
        guard case PhotoAccessError.unresolvable = BookmarkResolver.resolutionFailure(error, name: "x.jpg") else {
            return XCTFail("an unknown failure should not claim the file has moved")
        }
    }

    /// Relink is the repair for a lost token as much as for a lost target, so
    /// both are offered it.
    func testAPhotographWithAnUnresolvableBookmarkIsOfferedRelink() throws {
        let reference = try imported("broken.jpg")
        try destroy("broken.jpg")
        XCTAssertEqual(store.missingPhotographs().map(\.id), [reference.id])
    }
}
