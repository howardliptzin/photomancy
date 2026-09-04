import XCTest
import UniformTypeIdentifiers
@testable import PhotomancyCore

final class ThumbnailDecoderTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TestImages.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDecodesToTheRequestedLongestEdge() throws {
        let source = try TestImages.makeCGImage(width: 4000, height: 3000)
        let url = try TestImages.write(source, as: .jpeg, to: directory.appendingPathComponent("a.jpg"))

        let thumbnail = try ThumbnailDecoder.decode(url: url, maxPixelSize: 512)

        XCTAssertEqual(max(thumbnail.image.width, thumbnail.image.height), 512)
        XCTAssertEqual(thumbnail.aspectRatio, 4.0 / 3.0, accuracy: 0.01)
    }

    func testNeverDecodesTheFullImage() throws {
        let source = try TestImages.makeCGImage(width: 4000, height: 3000)
        let url = try TestImages.write(source, as: .jpeg, to: directory.appendingPathComponent("b.jpg"))

        let thumbnail = try ThumbnailDecoder.decode(url: url, maxPixelSize: 256)

        XCTAssertLessThanOrEqual(thumbnail.image.width, 256)
        XCTAssertLessThan(thumbnail.byteCount, 256 * 256 * 4 + 4096)
    }

    func testHandlesPNGAndHEIC() throws {
        let source = try TestImages.makeCGImage(width: 1200, height: 800, alpha: true)
        for type in [UTType.png, UTType.heic] {
            let url = try TestImages.write(
                source, as: type,
                to: directory.appendingPathComponent("c.\(type.preferredFilenameExtension ?? "img")")
            )
            let thumbnail = try ThumbnailDecoder.decode(url: url, maxPixelSize: 384)
            XCTAssertEqual(max(thumbnail.image.width, thumbnail.image.height), 384, "\(type.identifier)")
        }
    }

    /// A portrait frame from a phone is stored landscape with an orientation
    /// tag. If probe reported the stored dimensions, every such photograph would
    /// get the wrong aspect ratio and lay out sideways.
    func testProbeReportsOrientationCorrectedDimensions() throws {
        let source = try TestImages.makeCGImage(width: 4000, height: 3000)
        let url = try TestImages.write(
            source, as: .jpeg,
            to: directory.appendingPathComponent("rotated.jpg"),
            orientation: 6
        )

        let dimensions = try ThumbnailDecoder.probe(url: url)

        XCTAssertEqual(dimensions.width, 3000)
        XCTAssertEqual(dimensions.height, 4000)
    }

    func testDecodeAppliesOrientation() throws {
        let source = try TestImages.makeCGImage(width: 4000, height: 3000)
        let url = try TestImages.write(
            source, as: .jpeg,
            to: directory.appendingPathComponent("rotated2.jpg"),
            orientation: 6
        )

        let thumbnail = try ThumbnailDecoder.decode(url: url, maxPixelSize: 400)

        XCTAssertLessThan(thumbnail.image.width, thumbnail.image.height)
    }

    func testNonImageFails() throws {
        let url = directory.appendingPathComponent("not-a-photograph.jpg")
        try Data("hello".utf8).write(to: url)
        XCTAssertThrowsError(try ThumbnailDecoder.decode(url: url, maxPixelSize: 256))
    }
}
