import XCTest
import UIKit
@testable import KhanhScanner

final class DocumentEnhancerTests: XCTestCase {
    func testBrightensNeutralPaper() throws {
        let before = try components(solid(UIColor(white: 0.82, alpha: 1)))
        let after = try components(DocumentEnhancer().enhance(solid(UIColor(white: 0.82, alpha: 1))))
        XCTAssertGreaterThan(luminance(after), luminance(before))
        XCTAssertGreaterThan(luminance(after), 0.85)
    }

    func testKeepsDarkTextDark() throws {
        let after = try components(DocumentEnhancer().enhance(solid(UIColor(white: 0.12, alpha: 1))))
        XCTAssertLessThan(luminance(after), 0.3)
    }

    func testPreservesBlueAndRedInk() throws {
        let blue = try components(DocumentEnhancer().enhance(solid(UIColor(red: 0.08, green: 0.2, blue: 0.9, alpha: 1))))
        let red = try components(DocumentEnhancer().enhance(solid(UIColor(red: 0.9, green: 0.08, blue: 0.08, alpha: 1))))
        XCTAssertGreaterThan(blue.b, blue.r + 0.2)
        XCTAssertGreaterThan(red.r, red.b + 0.2)
        XCTAssertGreaterThan(saturation(blue), 0.35)
        XCTAssertGreaterThan(saturation(red), 0.35)
    }

    private func solid(_ color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    private func components(_ image: UIImage) throws -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (CGFloat(bytes[0]) / 255, CGFloat(bytes[1]) / 255, CGFloat(bytes[2]) / 255)
    }

    private func luminance(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat { 0.2126*c.r + 0.7152*c.g + 0.0722*c.b }
    private func saturation(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat {
        let hi = max(c.r, c.g, c.b), lo = min(c.r, c.g, c.b)
        return hi == 0 ? 0 : (hi - lo) / hi
    }
}
