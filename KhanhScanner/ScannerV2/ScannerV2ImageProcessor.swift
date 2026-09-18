import CoreImage
import ImageIO
import UIKit

enum ScannerV2ImageProcessor {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let sampleSize = 64

    static func sharpnessScore(of image: UIImage) -> Float {
        guard let cgImage = normalizedCGImage(from: image) else { return 0 }
        return sharpnessScore(of: cgImage)
    }

    static func sharpnessScore(of image: CGImage) -> Float {
        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: sampleSize,
                height: sampleSize,
                bitsPerComponent: 8,
                bytesPerRow: sampleSize,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
            return true
        }
        guard rendered else { return 0 }

        var total: Int = 0
        var comparisons = 0
        for y in 0..<sampleSize {
            for x in 0..<sampleSize {
                let index = y * sampleSize + x
                if x + 1 < sampleSize {
                    total += abs(Int(pixels[index]) - Int(pixels[index + 1]))
                    comparisons += 1
                }
                if y + 1 < sampleSize {
                    total += abs(Int(pixels[index]) - Int(pixels[index + sampleSize]))
                    comparisons += 1
                }
            }
        }

        guard comparisons > 0 else { return 0 }
        let meanGradient = Float(total) / Float(comparisons) / 255
        return min(1, meanGradient * 3)
    }

    static func correctedImage(
        from pixelBuffer: CVPixelBuffer,
        quadrilateral: ScannerV2Quadrilateral,
        orientation: CGImagePropertyOrientation = .right
    ) -> UIImage? {
        let input = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        return correctedImage(from: input, quadrilateral: quadrilateral)
    }

    static func correctedImage(
        from image: CIImage,
        quadrilateral: ScannerV2Quadrilateral
    ) -> UIImage? {
        guard !image.extent.isEmpty,
              let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            return nil
        }

        let extent = image.extent
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(vector(quadrilateral.topLeft, in: extent), forKey: "inputTopLeft")
        filter.setValue(vector(quadrilateral.topRight, in: extent), forKey: "inputTopRight")
        filter.setValue(vector(quadrilateral.bottomRight, in: extent), forKey: "inputBottomRight")
        filter.setValue(vector(quadrilateral.bottomLeft, in: extent), forKey: "inputBottomLeft")

        guard let output = filter.outputImage,
              !output.extent.isEmpty,
              let cgImage = context.createCGImage(output, from: output.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    static func cgImage(
        from pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .right
    ) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        return context.createCGImage(image, from: image.extent)
    }

    private static func vector(_ point: CGPoint, in extent: CGRect) -> CIVector {
        CIVector(
            x: extent.minX + point.x * extent.width,
            y: extent.minY + point.y * extent.height
        )
    }

    private static func normalizedCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }
}
