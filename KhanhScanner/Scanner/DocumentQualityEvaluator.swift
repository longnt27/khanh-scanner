import CoreGraphics
import UIKit

enum DocumentQuality: Equatable {
    case ready
    case flattenCorners
}

struct ScannedPageValidation {
    let acceptedPages: [UIImage]
    let rejectedPageCount: Int
}

enum ScannedPageQualityValidator {
    static let warningMessage = "Flatten all four corners before scanning."

    static func validate(_ pages: [UIImage]) -> ScannedPageValidation {
        validate(pages, evaluator: quality(of:))
    }

    static func validate(
        _ pages: [UIImage],
        evaluator: (UIImage) -> DocumentQuality
    ) -> ScannedPageValidation {
        var acceptedPages: [UIImage] = []
        var rejectedPageCount = 0

        for page in pages {
            switch evaluator(page) {
            case .ready:
                acceptedPages.append(page)
            case .flattenCorners:
                rejectedPageCount += 1
            }
        }

        return ScannedPageValidation(
            acceptedPages: acceptedPages,
            rejectedPageCount: rejectedPageCount
        )
    }

    static func quality(of image: UIImage) -> DocumentQuality {
        guard let image = image.normalizedCGImage else { return .flattenCorners }
        return DocumentCornerFoldAnalyzer.hasObviousFold(in: image) ? .flattenCorners : .ready
    }
}

private enum DocumentCornerFoldAnalyzer {
    private static let analysisSize = 256
    private static let comparisonOffset = 4
    private static let sampleCount = 18
    private static let minimumSeparation = 42.0
    private static let minimumSupportedFraction = 0.72
    private static let maximumOuterDeviation = 34.0

    static func hasObviousFold(in image: CGImage) -> Bool {
        guard let grayscaleImage = grayscaleImage(from: image) else { return false }

        for corner in Corner.allCases {
            for intercept in stride(from: 28, through: 76, by: 4) {
                if hasFoldBoundary(at: corner, intercept: intercept, image: grayscaleImage) {
                    return true
                }
            }
        }

        return false
    }

    private static func hasFoldBoundary(
        at corner: Corner,
        intercept: Int,
        image: GrayscaleImage
    ) -> Bool {
        var signedDifferences: [Double] = []
        var innerBoundaryValues: [Double] = []

        for index in 0..<sampleCount {
            let progress = 0.25 + 0.5 * (Double(index) + 0.5) / Double(sampleCount)
            let u = Double(intercept) * progress
            let v = Double(intercept) - u
            let outer = sample(
                at: corner,
                u: u - Double(comparisonOffset),
                v: v - Double(comparisonOffset),
                image: image
            )
            let inner = sample(
                at: corner,
                u: u + Double(comparisonOffset),
                v: v + Double(comparisonOffset),
                image: image
            )
            signedDifferences.append(Double(inner) - Double(outer))
            innerBoundaryValues.append(Double(inner))
        }

        let meanDifference = signedDifferences.reduce(0, +) / Double(signedDifferences.count)
        let supportedSamples = signedDifferences.filter {
            abs($0) >= minimumSeparation && ($0 > 0) == (meanDifference > 0)
        }.count
        let supportedFraction = Double(supportedSamples) / Double(signedDifferences.count)

        guard abs(meanDifference) >= minimumSeparation,
              supportedFraction >= minimumSupportedFraction else {
            return false
        }

        let outerValues = outerTriangleSamples(
            at: corner,
            intercept: intercept - comparisonOffset * 2,
            image: image
        )
        guard !outerValues.isEmpty else { return false }
        let mean = outerValues.reduce(0, +) / Double(outerValues.count)
        let innerMean = innerBoundaryValues.reduce(0, +) / Double(innerBoundaryValues.count)
        let variance = outerValues.reduce(0) { total, value in
            total + pow(value - mean, 2)
        } / Double(outerValues.count)
        return abs(innerMean - mean) >= minimumSeparation
            && sqrt(variance) <= maximumOuterDeviation
    }

    private static func outerTriangleSamples(
        at corner: Corner,
        intercept: Int,
        image: GrayscaleImage
    ) -> [Double] {
        guard intercept > 12 else { return [] }
        var values: [Double] = []
        let step = max(3, intercept / 8)

        for u in stride(from: 4, to: intercept, by: step) {
            for v in stride(from: 4, to: intercept - u, by: step) {
                values.append(Double(sample(
                    at: corner,
                    u: Double(u),
                    v: Double(v),
                    image: image
                )))
            }
        }

        return values
    }

    private static func sample(
        at corner: Corner,
        u: Double,
        v: Double,
        image: GrayscaleImage
    ) -> UInt8 {
        let localX = min(analysisSize - 1, max(0, Int(round(u))))
        let localY = min(analysisSize - 1, max(0, Int(round(v))))
        let x: Int
        let y: Int

        switch corner {
        case .topLeft:
            x = localX
            y = localY
        case .topRight:
            x = image.width - 1 - localX
            y = localY
        case .bottomRight:
            x = image.width - 1 - localX
            y = image.height - 1 - localY
        case .bottomLeft:
            x = localX
            y = image.height - 1 - localY
        }

        return image.pixels[y * image.width + x]
    }

    private static func grayscaleImage(from image: CGImage) -> GrayscaleImage? {
        let sourceWidth = max(1, image.width)
        let sourceHeight = max(1, image.height)
        let scale = CGFloat(analysisSize) / CGFloat(min(sourceWidth, sourceHeight))
        let width = max(analysisSize, Int(round(CGFloat(sourceWidth) * scale)))
        let height = max(analysisSize, Int(round(CGFloat(sourceHeight) * scale)))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? GrayscaleImage(pixels: pixels, width: width, height: height) : nil
    }

    private struct GrayscaleImage {
        let pixels: [UInt8]
        let width: Int
        let height: Int
    }

    private enum Corner: CaseIterable {
        case topLeft
        case topRight
        case bottomRight
        case bottomLeft
    }
}

private extension UIImage {
    var normalizedCGImage: CGImage? {
        if imageOrientation == .up, let cgImage { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
