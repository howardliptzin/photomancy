import XCTest
@testable import PhotomancyCore

final class SheetColorTests: XCTestCase {

    private let epsilon = 1e-9

    func testSixDigitHex() throws {
        let colour = try XCTUnwrap(SheetColor(hex: "#FF8000"))
        XCTAssertEqual(colour.red, 1, accuracy: epsilon)
        XCTAssertEqual(colour.green, 128.0 / 255.0, accuracy: epsilon)
        XCTAssertEqual(colour.blue, 0, accuracy: epsilon)
        XCTAssertEqual(colour.alpha, 1, accuracy: epsilon)
    }

    func testTheHashAndTheCaseAreOptional() {
        XCTAssertEqual(SheetColor(hex: "#ff8000"), SheetColor(hex: "FF8000"))
        XCTAssertEqual(SheetColor(hex: "  #Ff8000  "), SheetColor(hex: "ff8000"))
    }

    /// Shorthand doubles each digit — F0A is FF00AA, not 0F0A.
    func testShorthandExpandsByDoublingEachDigit() {
        XCTAssertEqual(SheetColor(hex: "#F0A"), SheetColor(hex: "#FF00AA"))
        XCTAssertEqual(SheetColor(hex: "#FFF"), .white)
        XCTAssertEqual(SheetColor(hex: "#000"), .black)
    }

    func testAlphaIsReadFromEightAndFourDigitForms() throws {
        let half = try XCTUnwrap(SheetColor(hex: "#00000080"))
        XCTAssertEqual(half.alpha, 128.0 / 255.0, accuracy: epsilon)
        XCTAssertEqual(SheetColor(hex: "#0008"), SheetColor(hex: "#00000088"))
    }

    func testUnreadableStringsAreNil() {
        for bad in ["", "#", "#12345", "#1234567", "nope", "#GGGGGG", "#12 34 56", "12345678901"] {
            XCTAssertNil(SheetColor(hex: bad), "\(bad) should not parse")
        }
    }

    func testRoundTripsThroughItsCanonicalForm() throws {
        for input in ["#FF8000", "#000000", "#FFFFFF", "#123456"] {
            let colour = try XCTUnwrap(SheetColor(hex: input))
            XCTAssertEqual(colour.hex, input)
            XCTAssertEqual(SheetColor(hex: colour.hex), colour)
        }
        XCTAssertEqual(SheetColor(hex: "#f0a")?.hex, "#FF00AA")
    }

    func testAlphaOnlyAppearsInTheCanonicalFormWhenItMatters() throws {
        XCTAssertEqual(try XCTUnwrap(SheetColor(hex: "#FF8000FF")).hex, "#FF8000")
        XCTAssertEqual(try XCTUnwrap(SheetColor(hex: "#FF800080")).hex, "#FF800080")
    }

    func testComponentsAreClamped() {
        let colour = SheetColor(red: 4, green: -2, blue: .nan, alpha: 100)
        XCTAssertEqual(colour.red, 1, accuracy: epsilon)
        XCTAssertEqual(colour.green, 0, accuracy: epsilon)
        XCTAssertEqual(colour.blue, 0, accuracy: epsilon)
        XCTAssertEqual(colour.alpha, 1, accuracy: epsilon)
    }

    func testTheCGColorIsSRGBWithMatchingComponents() throws {
        let colour = try XCTUnwrap(SheetColor(hex: "#3366CC"))
        let cg = colour.cgColor
        XCTAssertEqual(cg.colorSpace?.name, CGColorSpace.sRGB)
        let components = try XCTUnwrap(cg.components)
        XCTAssertEqual(Double(components[0]), colour.red, accuracy: 1e-6)
        XCTAssertEqual(Double(components[1]), colour.green, accuracy: 1e-6)
        XCTAssertEqual(Double(components[2]), colour.blue, accuracy: 1e-6)
    }

    // MARK: - Reading against the background

    func testContrastingInkFollowsTheBackground() {
        XCTAssertEqual(SheetColor.white.contrastingInk, .black)
        XCTAssertEqual(SheetColor.black.contrastingInk, .white)
        XCTAssertEqual(SheetColor(hex: "#EEEEEE")?.contrastingInk, .black)
        XCTAssertEqual(SheetColor(hex: "#222222")?.contrastingInk, .white)
    }

    /// Green reads far brighter than blue at the same value — a naive average
    /// would put white ink on a mid-green sheet.
    func testLuminanceIsWeightedByChannel() throws {
        let green = try XCTUnwrap(SheetColor(hex: "#00FF00"))
        let blue = try XCTUnwrap(SheetColor(hex: "#0000FF"))
        XCTAssertGreaterThan(green.relativeLuminance, blue.relativeLuminance)
        XCTAssertEqual(green.contrastingInk, .black)
        XCTAssertEqual(blue.contrastingInk, .white)
    }

    func testBlendingHitsBothEnds() {
        XCTAssertEqual(SheetColor.white.blended(toward: .black, amount: 0), .white)
        XCTAssertEqual(SheetColor.white.blended(toward: .black, amount: 1), .black)
        let half = SheetColor.white.blended(toward: .black, amount: 0.5)
        XCTAssertEqual(half.red, 0.5, accuracy: epsilon)
    }

    func testBlendAmountIsClamped() {
        XCTAssertEqual(SheetColor.white.blended(toward: .black, amount: 5), .black)
        XCTAssertEqual(SheetColor.white.blended(toward: .black, amount: -5), .white)
        XCTAssertEqual(SheetColor.white.blended(toward: .black, amount: .nan), .white)
    }

    /// The placeholder has to be visible on any sheet the person chooses, so it
    /// moves away from the background rather than toward a fixed grey.
    func testThePlaceholderTintMovesAwayFromTheBackgroundEitherWay() throws {
        let onWhite = SheetColor.white.placeholderTint
        XCTAssertLessThan(onWhite.relativeLuminance, SheetColor.white.relativeLuminance)

        let onBlack = SheetColor.black.placeholderTint
        XCTAssertGreaterThan(onBlack.relativeLuminance, SheetColor.black.relativeLuminance)

        // Quiet on both: it stands in for a photograph, it does not announce itself.
        XCTAssertLessThan(abs(onWhite.relativeLuminance - 1), 0.12)
        XCTAssertLessThan(abs(onBlack.relativeLuminance - 0), 0.12)
    }

    // MARK: - As a setting

    func testTheDefaultSheetBackgroundIsWhite() {
        XCTAssertEqual(SheetSettings().background, .white)
    }

    /// A malformed value must not be able to blank the sheet — an empty cell is
    /// background and nothing else, so this is what would be on the page.
    func testAnUnreadableSettingFallsBackToWhite() {
        var settings = SheetSettings()
        settings.backgroundHex = "not a colour"
        XCTAssertEqual(settings.background, .white)
    }

    func testASetBackgroundIsUsed() {
        var settings = SheetSettings()
        settings.backgroundHex = "#1A1A1A"
        XCTAssertEqual(settings.background, SheetColor(hex: "#1A1A1A"))
    }
}
