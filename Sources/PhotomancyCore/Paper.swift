import Foundation
import CoreGraphics

/// Where a sheet gets printed.
///
/// This does not shape the screen — the window does that. Paper is consulted only
/// when the rectangles `layout()` produced for the window are scaled onto a page.
/// It is remembered per collection because a collection tends to be printed the
/// same way each time, not because it constrains what is on screen.
///
/// A4 landscape is the default, which makes the default output a contact sheet.
public struct Paper: Codable, Sendable, Hashable {

    public enum Size: String, Codable, Sendable, Hashable, CaseIterable {
        case a4
        case usLetter

        /// Millimetres, portrait: width then height.
        var portraitMillimetres: CGSize {
            switch self {
            case .a4: CGSize(width: 210, height: 297)
            case .usLetter: CGSize(width: 215.9, height: 279.4)
            }
        }
    }

    public enum Orientation: String, Codable, Sendable, Hashable, CaseIterable {
        case portrait
        case landscape
    }

    public var size: Size
    public var orientation: Orientation

    public init(size: Size = .a4, orientation: Orientation = .landscape) {
        self.size = size
        self.orientation = orientation
    }

    public var millimetres: CGSize {
        let portrait = size.portraitMillimetres
        return orientation == .portrait
            ? portrait
            : CGSize(width: portrait.height, height: portrait.width)
    }

    /// PostScript points — 72 to the inch, which is what `CGContext` and
    /// `NSPrintInfo` both work in.
    public var points: CGSize {
        let millimetres = millimetres
        return CGSize(
            width: millimetres.width / 25.4 * 72,
            height: millimetres.height / 25.4 * 72
        )
    }

    /// Used to letterbox the window's sheet onto the page: the window's aspect
    /// will rarely match this, and the difference is blank paper on two sides.
    public var aspect: Double {
        let size = millimetres
        guard size.height > 0 else { return 1 }
        return size.width / size.height
    }

    enum CodingKeys: String, CodingKey {
        case size, orientation
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Paper()
        size = try container.decodeIfPresent(Size.self, forKey: .size) ?? fallback.size
        orientation = try container.decodeIfPresent(Orientation.self, forKey: .orientation) ?? fallback.orientation
    }
}
