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

    /// A colour from any colour space, converted into sRGB rather than
    /// reinterpreted.
    ///
    /// The system colour panel hands back colours in whatever space was picked —
    /// Display P3 among them. Reading those components as if they were sRGB
    /// would store, show and print a different colour from the one chosen.
    /// Always opaque: paper has no transparency. `nil` if it cannot be converted.
    public init?(convertingToSRGB color: CGColor) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: space, intent: .relativeColorimetric, options: nil),
              let components = converted.components, components.count >= 3
        else { return nil }
        self.init(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
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

    /// Perceived brightness, 0 to 1. Used to decide what will read against this.
    public var relativeLuminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// Black or white, whichever is legible on this colour. The sheet's
    /// background is the person's choice and can be anything, so nothing drawn
    /// over it may assume a light ground.
    public var contrastingInk: SheetColor {
        relativeLuminance > 0.5 ? .black : .white
    }

    /// Linear mix. `amount` 0 returns this colour, 1 returns the other.
    public func blended(toward other: SheetColor, amount: Double) -> SheetColor {
        let amount = amount.isFinite ? min(max(amount, 0), 1) : 0
        return SheetColor(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount,
            alpha: alpha + (other.alpha - alpha) * amount
        )
    }

    /// Stands in for a photograph that is still decoding. Barely visible, and
    /// derived from the background so it reads on a dark sheet as well as a
    /// light one. A cell with no photograph at all draws nothing instead.
    public var placeholderTint: SheetColor {
        blended(toward: contrastingInk, amount: 0.07)
    }

    /// Quiet text drawn on the background itself — the filename under a
    /// photograph in the lightbox. Derived from the background so it reads on a
    /// white sheet and a black one alike, without competing with the photograph.
    public var captionInk: SheetColor {
        blended(toward: contrastingInk, amount: 0.55)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension SheetColor {

    /// A background one click away, named for its tooltip.
    public struct Preset: Sendable, Hashable {
        public let name: String
        public let color: SheetColor
    }

    /// The backgrounds a sheet most often wants: white, black, and a mid grey.
    /// Anything else is the colour well beside them.
    public static let presets: [Preset] = [
        Preset(name: "White", color: .white),
        Preset(name: "Black", color: .black),
        Preset(name: "Grey (#939292)", color: SheetColor(red: 0x93 / 255.0, green: 0x92 / 255.0, blue: 0x92 / 255.0)),
    ]
}

extension SheetSettings {
    /// The stored string resolved to a colour, falling back to white when it is
    /// unreadable. A malformed hex must not be able to blank the sheet.
    public var background: SheetColor {
        SheetColor(hex: backgroundHex) ?? .white
    }
}
