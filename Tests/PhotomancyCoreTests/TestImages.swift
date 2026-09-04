import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Synthesises real encoded files, so the decode tests go through ImageIO
/// exactly as the app does rather than through a mock.
enum TestImages {

    static func makeCGImage(width: Int, height: Int, alpha: Bool = false) throws -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let info: CGBitmapInfo = alpha
            ? CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            : CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info.rawValue
        ) else {
            throw XCTSkip("could not create a bitmap context")
        }
        // Something with structure, so a resample is visibly a resample.
        for row in 0..<8 {
            for column in 0..<8 {
                context.setFillColor(
                    red: Double(column) / 8, green: Double(row) / 8, blue: 0.5, alpha: 1
                )
                context.fill(CGRect(
                    x: Double(column) * Double(width) / 8,
                    y: Double(row) * Double(height) / 8,
                    width: Double(width) / 8,
                    height: Double(height) / 8
                ))
            }
        }
        guard let image = context.makeImage() else { throw XCTSkip("could not render") }
        return image
    }

    @discardableResult
    static func write(
        _ image: CGImage,
        as type: UTType,
        to url: URL,
        orientation: Int? = nil
    ) throws -> URL {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, 1, nil
        ) else {
            throw XCTSkip("\(type.identifier) cannot be written on this machine")
        }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("could not finalise \(type.identifier)")
        }
        return url
    }

    static func temporaryDirectory(_ function: String = #function) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photomancy-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
