import XCTest
import UIKit
@testable import KhanhScanner

final class DocumentEnhancerTests: XCTestCase {
    func testBrightensPaperAndPreservesColoredInk() throws {
        let input = fixture()
        let output = try DocumentEnhancer().enhance(input)
        let background = try pixel(output, x: 10, y: 10)
        let black = try pixel(output, x: 35, y: 35)
        let blue = try pixel(output, x: 75, y: 35)
        let red = try pixel(output, x: 115, y: 35)

        XCTAssertGreaterThan(luminance(background), 0.9)
        XCTAssertLessThan(luminance(black), 0.25)
        XCTAssertGreaterThan(blue.b, blue.r + 0.2)
        XCTAssertGreaterThan(red.r, red.b + 0.2)
        XCTAssertGreaterThan(saturation(blue), 0.35)
        XCTAssertGreaterThan(saturation(red), 0.35)
    }

    private func fixture() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 150, height: 70)).image { ctx in
            UIColor(white: 0.82, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 150, height: 70))
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(x: 25, y: 25, width: 20, height: 20))
            UIColor(red: 0.08, green: 0.2, blue: 0.9, alpha: 1).setFill(); ctx.fill(CGRect(x: 65, y: 25, width: 20, height: 20))
            UIColor(red: 0.9, green: 0.08, blue: 0.08, alpha: 1).setFill(); ctx.fill(CGRect(x: 105, y: 25, width: 20, height: 20))
        }
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) throws -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: CGFloat(-x), y: CGFloat(y - cg.height + 1))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return (CGFloat(bytes[0]) / 255, CGFloat(bytes[1]) / 255, CGFloat(bytes[2]) / 255)
    }

    private func luminance(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat { 0.2126*c.r + 0.7152*c.g + 0.0722*c.b }
    private func saturation(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat {
        let hi = max(c.r, c.g, c.b), lo = min(c.r, c.g, c.b)
        return hi == 0 ? 0 : (hi - lo) / hi
    }
}
