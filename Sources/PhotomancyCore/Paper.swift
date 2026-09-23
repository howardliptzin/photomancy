import Foundation
import CoreGraphics

/// Where a sheet gets printed.
///
/// This does not shape the screen — the window does that. Paper is consulted only
/// when the rectangles `sheetGeometry()` produced for the window are scaled onto a
/// page. It is remembered per collection because a collection tends to be printed
/// the same way each time, not because it constrains what is on screen.
///
/// A4 landscape is the default, which makes the default output a contact sheet.
///
/// ## Why there are two ways to say the same thing
///
/// Whatever paper the print panel ends on is remembered — A3, 13 × 19, a roll,
/// anything the printer offers. That could not be done by adding cases to
/// ``Size``, and the reason is a one-way door in the library file. A build that
/// predates a new case throws when it decodes it; `LibraryStore.load()` then
/// refuses to overwrite a file it could not read, and the person opens a
/// reverted build to a library it cannot open.
///
/// Since 2026-09-23 an unknown size or orientation decodes to the default
/// instead of throwing, but every build before that still throws, so the rule
/// stands. ``Size`` is frozen at the two cases it shipped with and **never gains
/// another**. The real paper lives in ``pointSize``, under keys an older build
/// does not know and therefore ignores. ``size`` and ``orientation`` are still
/// written on every save, set to the nearest of the two shapes, so a reverted
/// build loads the library and prints on something close rather than not
/// loading at all.
public struct Paper: Codable, Sendable, Hashable {

    /// **Frozen. Never add a case.** See the note on the type.
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

        /// Unknown reads as A4 rather than throwing — see ``CellShape``.
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Size(rawValue: raw) ?? .a4
        }
    }

    public enum Orientation: String, Codable, Sendable, Hashable, CaseIterable {
        case portrait
        case landscape

        /// Unknown reads as landscape, the default, rather than throwing.
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Orientation(rawValue: raw) ?? .landscape
        }
    }

    /// The nearest of the two shapes an older build understands. Written on
    /// every save; authoritative only when ``pointSize`` is absent.
    public var size: Size
    public var orientation: Orientation

    /// The paper actually chosen, in points. Authoritative when present.
    public var pointSize: CGSize?

    /// The printer's own name for it — `iso-a4`, `na-letter`, `iso-a3`. Kept so
    /// the panel can be reopened on the same paper rather than on something
    /// merely the same size.
    public var paperName: String?

    public init(size: Size = .a4, orientation: Orientation = .landscape) {
        self.size = size
        self.orientation = orientation
        self.pointSize = nil
        self.paperName = nil
    }

    /// Any paper at all, as the print panel reports it.
    public init(points: CGSize, name: String? = nil) {
        guard points.width.isFinite, points.height.isFinite,
              points.width > 0, points.height > 0 else {
            self = Paper()
            return
        }
        self.orientation = points.width > points.height ? .landscape : .portrait
        self.size = Paper.nearest(to: points)
        self.pointSize = points
        self.paperName = name
    }

    /// PostScript points — 72 to the inch, which is what `CGContext` and
    /// `NSPrintInfo` both work in.
    public var points: CGSize {
        if let pointSize, pointSize.width.isFinite, pointSize.height.isFinite,
           pointSize.width > 0, pointSize.height > 0 {
            return pointSize
        }
        let portrait = size.portraitMillimetres
        let inPoints = CGSize(width: portrait.width / 25.4 * 72, height: portrait.height / 25.4 * 72)
        return orientation == .portrait
            ? inPoints
            : CGSize(width: inPoints.height, height: inPoints.width)
    }

    public var millimetres: CGSize {
        // Straight from the table when the paper is one of the frozen two.
        // Going out to points and back loses the exact figure — A4 landscape
        // comes home 210.00000000000003 mm tall — and those two sizes are
        // named in millimetres in the first place.
        guard pointSize != nil else {
            let portrait = size.portraitMillimetres
            return orientation == .portrait
                ? portrait
                : CGSize(width: portrait.height, height: portrait.width)
        }
        let points = points
        return CGSize(width: points.width / 72 * 25.4, height: points.height / 72 * 25.4)
    }

    /// Used to letterbox the window's sheet onto the page: the block's aspect
    /// will rarely match this, and the difference is blank paper on two sides.
    public var aspect: Double {
        let size = points
        guard size.height > 0 else { return 1 }
        return size.width / size.height
    }

    /// Which of the two frozen shapes is closest, compared on the short and
    /// long edges so orientation does not confuse the answer.
    static func nearest(to points: CGSize) -> Size {
        let short = min(points.width, points.height)
        let long = max(points.width, points.height)
        var best = Size.a4
        var bestDistance = Double.infinity
        for candidate in Size.allCases {
            let millimetres = candidate.portraitMillimetres
            let width = millimetres.width / 25.4 * 72
            let height = millimetres.height / 25.4 * 72
            let distance = pow(short - width, 2) + pow(long - height, 2)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }

    // MARK: - Stored form

    /// `pointWidth` and `pointHeight` rather than one `CGSize`: two plain
    /// numbers are legible in the library file and do not depend on how
    /// CoreGraphics happens to encode a size this year.
    enum CodingKeys: String, CodingKey {
        case size, orientation, pointWidth, pointHeight, paperName
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Paper()
        size = try container.decodeIfPresent(Size.self, forKey: .size) ?? fallback.size
        orientation = try container.decodeIfPresent(Orientation.self, forKey: .orientation) ?? fallback.orientation
        paperName = try container.decodeIfPresent(String.self, forKey: .paperName)

        let width = try container.decodeIfPresent(Double.self, forKey: .pointWidth)
        let height = try container.decodeIfPresent(Double.self, forKey: .pointHeight)
        if let width, let height, width > 0, height > 0 {
            pointSize = CGSize(width: width, height: height)
        } else {
            pointSize = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Always written, and always the nearest frozen shape, so a build that
        // knows nothing of the keys below still loads this library.
        try container.encode(size, forKey: .size)
        try container.encode(orientation, forKey: .orientation)
        try container.encodeIfPresent(pointSize.map { Double($0.width) }, forKey: .pointWidth)
        try container.encodeIfPresent(pointSize.map { Double($0.height) }, forKey: .pointHeight)
        try container.encodeIfPresent(paperName, forKey: .paperName)
    }
}
