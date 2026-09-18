import CoreImage
import ImageIO
import UIKit

struct ScannerV2DocumentSignals: Equatable {
    let sharpness: Float
    let fingerprint: ScannerV2PageFingerprint
}

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

    static func trimBackgroundSlivers(
        from image: UIImage,
        maximumTrimFraction: CGFloat = 0.06
    ) -> UIImage? {
        guard let cgImage = normalizedCGImage(from: image),
              cgImage.width > 8,
              cgImage.height > 8 else {
            return nil
        }

        let sourceWidth = cgImage.width
        let sourceHeight = cgImage.height
        let maxAnalysisDimension = 180
        let analysisScale = min(
            1,
            CGFloat(maxAnalysisDimension) / CGFloat(max(sourceWidth, sourceHeight))
        )
        let analysisWidth = max(8, Int((CGFloat(sourceWidth) * analysisScale).rounded()))
        let analysisHeight = max(8, Int((CGFloat(sourceHeight) * analysisScale).rounded()))

        var pixels = [UInt8](repeating: 0, count: analysisWidth * analysisHeight)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: analysisWidth,
                height: analysisHeight,
                bitsPerComponent: 8,
                bytesPerRow: analysisWidth,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: analysisWidth, height: analysisHeight)
            )
            return true
        }
        guard rendered else { return image }

        let sorted = pixels.sorted()
        let paperIndex = min(
            sorted.count - 1,
            Int(Double(sorted.count - 1) * 0.88)
        )
        let paperLuma = CGFloat(sorted[paperIndex]) / 255
        let paperThreshold = UInt8(
            max(0, min(255, Int((max(0.48, paperLuma - 0.20) * 255).rounded())))
        )

        let maxTrimX = max(1, Int(CGFloat(analysisWidth) * maximumTrimFraction))
        let maxTrimY = max(1, Int(CGFloat(analysisHeight) * maximumTrimFraction))

        func columnPaperFraction(_ x: Int) -> CGFloat {
            let start = analysisHeight / 12
            let end = analysisHeight - start
            guard end > start else { return 1 }
            var paper = 0
            for y in start..<end where pixels[y * analysisWidth + x] >= paperThreshold {
                paper += 1
            }
            return CGFloat(paper) / CGFloat(end - start)
        }

        func rowPaperFraction(_ y: Int) -> CGFloat {
            let start = analysisWidth / 12
            let end = analysisWidth - start
            guard end > start else { return 1 }
            var paper = 0
            for x in start..<end where pixels[y * analysisWidth + x] >= paperThreshold {
                paper += 1
            }
            return CGFloat(paper) / CGFloat(end - start)
        }

        func trimFromStart(
            limit: Int,
            fraction: (Int) -> CGFloat
        ) -> Int {
            guard fraction(0) < 0.72 else { return 0 }
            guard limit > 0 else { return 0 }

            for index in 1...limit {
                let current = fraction(index)
                let next = index < limit ? fraction(index + 1) : current
                if current >= 0.78, next >= 0.78 {
                    return index
                }
            }
            return 0
        }

        func trimFromEnd(
            length: Int,
            limit: Int,
            fraction: (Int) -> CGFloat
        ) -> Int {
            let last = length - 1
            guard last >= 0, fraction(last) < 0.72 else { return 0 }
            guard limit > 0 else { return 0 }

            for offset in 1...limit {
                let index = last - offset
                guard index >= 0 else { break }
                let current = fraction(index)
                let previous = index > 0 ? fraction(index - 1) : current
                if current >= 0.78, previous >= 0.78 {
                    return offset
                }
            }
            return 0
        }

        let left = trimFromStart(limit: maxTrimX, fraction: columnPaperFraction)
        let right = trimFromEnd(
            length: analysisWidth,
            limit: maxTrimX,
            fraction: columnPaperFraction
        )
        let bottom = trimFromStart(limit: maxTrimY, fraction: rowPaperFraction)
        let top = trimFromEnd(
            length: analysisHeight,
            limit: maxTrimY,
            fraction: rowPaperFraction
        )

        guard left + right > 0 || top + bottom > 0 else { return image }

        let xScale = CGFloat(sourceWidth) / CGFloat(analysisWidth)
        let yScale = CGFloat(sourceHeight) / CGFloat(analysisHeight)
        let crop = CGRect(
            x: CGFloat(left) * xScale,
            y: CGFloat(bottom) * yScale,
            width: CGFloat(sourceWidth) - CGFloat(left + right) * xScale,
            height: CGFloat(sourceHeight) - CGFloat(top + bottom) * yScale
        ).integral

        guard crop.width >= CGFloat(sourceWidth) * 0.88,
              crop.height >= CGFloat(sourceHeight) * 0.88,
              let cropped = cgImage.cropping(to: crop) else {
            return image
        }

        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    static func documentSignals(
        from image: CIImage,
        quadrilateral: ScannerV2Quadrilateral
    ) -> ScannerV2DocumentSignals? {
        guard let corrected = correctedImage(from: image, quadrilateral: quadrilateral),
              let fingerprint = pageFingerprint(of: corrected) else {
            return nil
        }

        return ScannerV2DocumentSignals(
            sharpness: sharpnessScore(of: corrected),
            fingerprint: fingerprint
        )
    }

    static func documentSignals(
        from pixelBuffer: CVPixelBuffer,
        quadrilateral: ScannerV2Quadrilateral,
        orientation: CGImagePropertyOrientation = .right
    ) -> ScannerV2DocumentSignals? {
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        return documentSignals(from: image, quadrilateral: quadrilateral)
    }

    static func manualPerspectiveCrop(
        from image: UIImage,
        quadrilateral: ScannerV2Quadrilateral
    ) -> UIImage? {
        guard let cgImage = normalizedCGImage(from: image),
              let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            return nil
        }

        let input = CIImage(cgImage: cgImage)
        let extent = input.extent
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(vector(quadrilateral.topLeft, in: extent), forKey: "inputTopLeft")
        filter.setValue(vector(quadrilateral.topRight, in: extent), forKey: "inputTopRight")
        filter.setValue(vector(quadrilateral.bottomRight, in: extent), forKey: "inputBottomRight")
        filter.setValue(vector(quadrilateral.bottomLeft, in: extent), forKey: "inputBottomLeft")

        guard let output = filter.outputImage,
              !output.extent.isEmpty,
              let rendered = context.createCGImage(output, from: output.extent) else {
            return nil
        }

        return UIImage(cgImage: rendered, scale: image.scale, orientation: .up)
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

        let corrected = UIImage(cgImage: cgImage)
        return trimBackgroundSlivers(from: corrected) ?? corrected
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
