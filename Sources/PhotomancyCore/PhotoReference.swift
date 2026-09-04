import Foundation
import CoreGraphics

/// A photograph the library knows about.
///
/// Note what is *not* here: a `URL`, or any public way to get one. The bookmark
/// is `internal` on purpose. Reading a photograph goes through
/// ``BookmarkResolver/withAccess(_:_:)``, which starts and stops security-scoped
/// access around the read. If a bare URL could be obtained, some later code
/// would eventually read through it without redeeming the bookmark, and that bug
/// is invisible until the second launch.
public struct PhotoReference: Identifiable, Codable, Sendable, Hashable {

    public let id: ContentHash
    /// The filename at import. For display and for the relink flow only —
    /// never for identity.
    public let displayName: String
    public let fileSize: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let addedAt: Date

    /// A security-scoped bookmark. The only durable permission an App Store app
    /// has to reopen a file the person chose in an earlier launch.
    var bookmark: Data

    init(
        id: ContentHash,
        displayName: String,
        fileSize: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        addedAt: Date = Date(),
        bookmark: Data
    ) {
        self.id = id
        self.displayName = displayName
        self.fileSize = fileSize
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.addedAt = addedAt
        self.bookmark = bookmark
    }

    public var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }

    /// Width over height. 1.0 if the dimensions are unusable, so callers never
    /// divide by zero.
    public var aspectRatio: Double {
        guard pixelWidth > 0, pixelHeight > 0 else { return 1 }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    /// Same photograph, new permission token.
    func replacingBookmark(with data: Data) -> PhotoReference {
        var copy = self
        copy.bookmark = data
        return copy
    }
}
