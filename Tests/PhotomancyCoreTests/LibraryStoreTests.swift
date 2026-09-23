import XCTest
@testable import PhotomancyCore

/// The library file on disk is the one thing the app cannot rebuild. These are
/// about never losing it.
///
/// Written 2026-09-23, when an audit found that the guarantee they check — an
/// unreadable library is never written over — had been documented since M3 and
/// never built: `load()` carried on with an empty document, and the save on quit
/// wrote it over the file.
@MainActor
final class LibraryStoreTests: XCTestCase {

    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("library.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("photomancy-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A library with two collections, as a newer build or an older one would
    /// write it — the shape of the real file, not a fixture invented for this.
    private func libraryJSON() throws -> String {
        var document = LibraryDocument()
        document.addCollection(named: "Real Via Mentana")
        document.addCollection(named: "Vintage")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(document), as: UTF8.self)
    }

    /// Files no build can read: cut off mid-write, and the right keys holding
    /// the wrong kind of value.
    private func unreadableLibraries() throws -> [(name: String, bytes: Data)] {
        let json = try libraryJSON()
        return [
            ("truncated", Data(json.prefix(json.count / 2).utf8)),
            ("wrong types", Data(json.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : \"two\"").utf8)),
        ]
    }

    // MARK: - Never written over

    func testAnUnreadableLibraryIsNeverWrittenOver() async throws {
        for library in try unreadableLibraries() {
            try library.bytes.write(to: file)

            let store = LibraryStore(fileURL: file)
            store.load()
            XCTAssertTrue(store.document.collections.isEmpty, library.name)

            // Everything that saves: an edit, the debounced save it schedules,
            // and the save on quit.
            store.addCollection(named: "Made after the failed load")
            try await Task.sleep(for: .milliseconds(400))
            store.saveNow()

            XCTAssertEqual(try Data(contentsOf: file), library.bytes,
                           "\(library.name): the unreadable library was written over")
        }
    }

    func testAFailedLoadSaysWhy() throws {
        try XCTUnwrap(try unreadableLibraries().first).bytes.write(to: file)
        let store = LibraryStore(fileURL: file)
        store.load()
        XCTAssertNotNil(store.loadFailure)
        XCTAssertTrue(store.isLoaded, "the empty state must still be allowed to show")
    }

    // MARK: - The way out

    /// Setting it aside keeps every byte of the old file, and only then lets a
    /// new library be saved.
    func testSettingAnUnreadableLibraryAsideKeepsItAndStartsAfresh() throws {
        let unreadable = try XCTUnwrap(try unreadableLibraries().first).bytes
        try unreadable.write(to: file)
        let store = LibraryStore(fileURL: file)
        store.load()

        let when = Date(timeIntervalSince1970: 1_790_000_000)
        let aside = try XCTUnwrap(try store.setAsideUnreadableLibrary(at: when))

        XCTAssertEqual(aside.deletingLastPathComponent().standardizedFileURL,
                       directory.standardizedFileURL, "kept beside where it was")
        XCTAssertTrue(aside.lastPathComponent.hasPrefix("library-unreadable-"))
        XCTAssertEqual(try Data(contentsOf: aside), unreadable, "every byte kept")
        XCTAssertNil(store.loadFailure)

        store.addCollection(named: "New")
        store.saveNow()
        let reopened = LibraryStore(fileURL: file)
        reopened.load()
        XCTAssertNil(reopened.loadFailure)
        XCTAssertEqual(reopened.document.collections.map(\.name), ["New"])
        XCTAssertEqual(try Data(contentsOf: aside), unreadable, "still there, untouched")
    }

    func testThereIsNothingToSetAsideWhenTheLibraryWasRead() throws {
        try Data(try libraryJSON().utf8).write(to: file)
        let store = LibraryStore(fileURL: file)
        store.load()
        XCTAssertNil(store.loadFailure)
        XCTAssertNil(try store.setAsideUnreadableLibrary())
        XCTAssertEqual(store.document.collections.count, 2, "a readable library is left alone")
    }

    /// First launch has no file at all, and that is not a failure: it must save.
    func testNoLibraryYetIsNotAFailure() throws {
        let store = LibraryStore(fileURL: file)
        store.load()
        XCTAssertNil(store.loadFailure)
        store.addCollection(named: "First")
        store.saveNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    // MARK: - Newer builds

    /// Unknown values from a newer build — a cell shape, a paper size and an
    /// orientation this build has never heard of — cost those settings their
    /// defaults, never the library.
    func testALibraryFromANewerBuildStillOpens() throws {
        let newer = try libraryJSON()
            .replacingOccurrences(of: "\"derivedFromCollection\"", with: "\"fiveByFour\"")
            .replacingOccurrences(of: "\"a4\"", with: "\"a3\"")
            .replacingOccurrences(of: "\"landscape\"", with: "\"panoramic\"")
        XCTAssertTrue(newer.contains("fiveByFour") && newer.contains("a3") && newer.contains("panoramic"),
                      "the fixture must really carry the unknown values")
        try Data(newer.utf8).write(to: file)

        let store = LibraryStore(fileURL: file)
        store.load()

        XCTAssertEqual(store.document.collections.map(\.name), ["Real Via Mentana", "Vintage"])
        let settings = try XCTUnwrap(store.document.collections.first).settings
        XCTAssertEqual(settings.cellShape, .derivedFromCollection)
        XCTAssertEqual(settings.paper.size, .a4)
        XCTAssertEqual(settings.paper.orientation, .landscape)
    }
}
