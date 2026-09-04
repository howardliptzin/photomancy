import XCTest
@testable import PhotomancyCore

final class ContentHashTests: XCTestCase {

    func testSameBytesGiveSameHash() {
        let a = ContentHasher.hash(Data("a photograph".utf8))
        let b = ContentHasher.hash(Data("a photograph".utf8))
        XCTAssertEqual(a, b)
    }

    func testDifferentBytesGiveDifferentHash() {
        let a = ContentHasher.hash(Data("a photograph".utf8))
        let b = ContentHasher.hash(Data("a photograph."[...].utf8))
        XCTAssertNotEqual(a, b)
    }

    func testHashIsSixtyFourHexCharacters() {
        let hash = ContentHasher.hash(Data())
        XCTAssertEqual(hash.hex.count, 64)
        XCTAssertTrue(hash.hex.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    /// The streaming file hash must agree with the in-memory one, including for
    /// payloads larger than one chunk — otherwise identity would depend on how
    /// the bytes happened to arrive.
    func testFileHashMatchesDataHashAcrossChunkBoundary() throws {
        var bytes = Data()
        bytes.reserveCapacity(ContentHasher.chunkSize * 2 + 17)
        for index in 0..<(ContentHasher.chunkSize * 2 + 17) {
            bytes.append(UInt8(index % 251))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photomancy-hash-\(UUID().uuidString).bin")
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(try ContentHasher.hash(contentsOf: url), ContentHasher.hash(bytes))
    }

    /// Identity survives a rename. This is the whole reason it is a content hash.
    func testHashSurvivesRename() throws {
        let directory = FileManager.default.temporaryDirectory
        let first = directory.appendingPathComponent("before-\(UUID().uuidString).bin")
        let second = directory.appendingPathComponent("after-\(UUID().uuidString).bin")
        try Data("stable bytes".utf8).write(to: first)
        defer { try? FileManager.default.removeItem(at: second) }

        let before = try ContentHasher.hash(contentsOf: first)
        try FileManager.default.moveItem(at: first, to: second)
        let after = try ContentHasher.hash(contentsOf: second)

        XCTAssertEqual(before, after)
    }

    func testCodesAsAPlainString() throws {
        let hash = ContentHasher.hash(Data("x".utf8))
        let encoded = try JSONEncoder().encode(hash)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"\(hash.hex)\"")
        XCTAssertEqual(try JSONDecoder().decode(ContentHash.self, from: encoded), hash)
    }
}
