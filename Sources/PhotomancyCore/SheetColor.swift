import Foundation
import CoreGraphics

/// The sheet's background, as components rather than as any one framework's
/// colour type.
///
/// The same rule as the geometry: the value is shared, the drawing is not. The
/// screen builds a SwiftUI `Color` from these components and the print path
/// builds a `CGColor`, both in sRGB, so a background cannot mean one thing on
/// the display and another on paper.
///
/// This carries more weight than a colour setting usually does. An empty cell is
/// background and nothing else — no outline, no placeholder — so on a grid that
/// is not full this *is* what is on the page.
public struct SheetColor: Sendable, Hashable {

    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        func clamp(_ value: Double) -> Double {
            guard value.isFinite else { return 0 }
            return min(max(value, 0), 1)
        }
        self.red = clamp(red)
        self.green = clamp(green)
        self.blue = clamp(blue)
        self.alpha = clamp(alpha)
    }

    public static let white = SheetColor(red: 1, green: 1, blue: 1)
    public static let black = SheetColor(red: 0, green: 0, blue: 0)

    /// Accepts `#RGB`, `#RGBA`, `#RRGGBB` and `#RRGGBBAA`, with or without the
    /// hash, in either case. Anything else is `nil` — the caller falls back to a
    /// default rather than showing an empty sheet.
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }

        // Shorthand doubles each digit: F0A is FF00AA, not 0F0A.
        switch digits.count {
        case 3, 4:
            digits = digits.map { "\($0)\($0)" }.joined()
        case 6, 8:
            break
        default:
            return nil
        }

        func channel(_ offset: Int) -> Double {
            let start = digits.index(digits.startIndex, offsetBy: offset)
            let end = digits.index(start, offsetBy: 2)
            return Double(UInt8(digits[start..<end], radix: 16) ?? 0) / 255
        }

        self.init(
            red: channel(0),
            green: channel(2),
            blue: channel(4),
            alpha: digits.count == 8 ? channel(6) : 1
        )
    }

    /// Canonical form: `#RRGGBB`, or `#RRGGBBAA` when it is not opaque.
    public var hex: String {
        func byte(_ value: Double) -> String {
            String(format: "%02X", Int((value * 255).rounded()))
        }
        let opaque = "#\(byte(red))\(byte(green))\(byte(blue))"
        return alpha >= 1 ? opaque : opaque + byte(alpha)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension SheetSettings {
    /// The stored string resolved to a colour, falling back to white when it is
    /// unreadable. A malformed hex must not be able to blank the sheet.
    public var background: SheetColor {
        SheetColor(hex: backgroundHex) ?? .white
    }
}
