import CoreImage
import ImageIO
import UIKit

struct ScannerV2PageFingerprint: Equatable {
    let bits: [UInt8]

    func distance(to other: ScannerV2PageFingerprint) -> Float {
        guard bits.count == other.bits.count, !bits.isEmpty else { return 1 }
        let changed = zip(bits, other.bits).reduce(0) { count, pair in
            count + (pair.0 == pair.1 ? 0 : 1)
        }
        return Float(changed) / Float(bits.count)
    }
}

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

        var gradients: [UInt8] = []
        gradients.reserveCapacity(sampleSize * sampleSize * 2)

        for y in 0..<sampleSize {
            for x in 0..<sampleSize {
                let index = y * sampleSize + x
                if x + 1 < sampleSize {
                    gradients.append(UInt8(abs(Int(pixels[index]) - Int(pixels[index + 1]))))
                }
                if y + 1 < sampleSize {
                    gradients.append(UInt8(abs(Int(pixels[index]) - Int(pixels[index + sampleSize]))))
                }
            }
        }

        guard !gradients.isEmpty else { return 0 }

        // Document pages are mostly blank paper, so averaging every pixel edge
        // punishes perfectly sharp pages that contain only a few lines of text.
        // Measure the strongest high-frequency detail instead. Blur lowers these
        // peaks while blank areas no longer drown the signal.
        gradients.sort(by: >)
        let tailCount = max(64, gradients.count / 20)
        let strongEdges = gradients.prefix(tailCount)
        let meanStrongGradient = Float(strongEdges.reduce(0) { $0 + Int($1) })
            / Float(strongEdges.count)
            / 255
        return min(1, meanStrongGradient)
    }

    static func pageFingerprint(of image: UIImage) -> ScannerV2PageFingerprint? {
        guard let cgImage = normalizedCGImage(from: image) else { return nil }

        let size = 16
        var pixels = [UInt8](repeating: 0, count: size * size)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }

            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard rendered else { return nil }

        let mean = pixels.reduce(0) { $0 + Int($1) } / pixels.count
        let bits = pixels.map { $0 < UInt8(mean) ? UInt8(1) : UInt8(0) }
        return ScannerV2PageFingerprint(bits: bits)
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
