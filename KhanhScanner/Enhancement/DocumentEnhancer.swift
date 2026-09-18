import CoreImage
import UIKit

final class DocumentEnhancer {
    enum EnhancementError: Error { case invalidImage, renderFailed }
    private static let context = CIContext(options: [.cacheIntermediates: true])

    func enhance(_ image: UIImage) throws -> UIImage {
        guard let cg = image.cgImage else { throw EnhancementError.invalidImage }
        let input = CIImage(cgImage: cg)

        let balanced = applyPaperWhiteBalance(to: input, source: cg)

        // Push light paper toward white and dark text toward black without
        // removing saturation. White balance happens first so pages captured
        // under different color temperatures converge on the same paper tone.
        let controls = CIFilter(name: "CIColorControls")
        controls?.setValue(balanced, forKey: kCIInputImageKey)
        controls?.setValue(1.18, forKey: kCIInputContrastKey)
        controls?.setValue(0.08, forKey: kCIInputBrightnessKey)
        controls?.setValue(1.08, forKey: kCIInputSaturationKey)

        guard let output = controls?.outputImage,
              let rendered = Self.context.createCGImage(output, from: input.extent) else {
            throw EnhancementError.renderFailed
        }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: .up)
    }

    private func applyPaperWhiteBalance(to image: CIImage, source: CGImage) -> CIImage {
        guard let reference = paperReferenceColor(from: source) else { return image }

        let linearReference = (
            r: linearSRGB(reference.r),
            g: linearSRGB(reference.g),
            b: linearSRGB(reference.b)
        )
        let target = max(linearReference.r, linearReference.g, linearReference.b)
        guard target > 0.08 else { return image }

        let rGain = clamp(target / max(linearReference.r, 0.001), min: 0.75, max: 1.55)
        let gGain = clamp(target / max(linearReference.g, 0.001), min: 0.75, max: 1.55)
        let bGain = clamp(target / max(linearReference.b, 0.001), min: 0.75, max: 1.55)

        guard let toLinear = CIFilter(name: "CISRGBToneCurveToLinear"),
              let matrix = CIFilter(name: "CIColorMatrix"),
              let toSRGB = CIFilter(name: "CILinearToSRGBToneCurve") else {
            return image
        }

        toLinear.setValue(image, forKey: kCIInputImageKey)
        guard let linearImage = toLinear.outputImage else { return image }

        matrix.setValue(linearImage, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: rGain, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: gGain, z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: bGain, w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")

        guard let balancedLinear = matrix.outputImage else { return image }
        toSRGB.setValue(balancedLinear, forKey: kCIInputImageKey)
        return toSRGB.outputImage ?? image
    }

    private func paperReferenceColor(from image: CGImage) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        let side = 32
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard rendered else { return nil }

        var samples: [(luma: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] = []
        samples.reserveCapacity(side * side)

        for index in stride(from: 0, to: bytes.count, by: 4) {
            let r = CGFloat(bytes[index]) / 255
            let g = CGFloat(bytes[index + 1]) / 255
            let b = CGFloat(bytes[index + 2]) / 255
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            samples.append((luma, r, g, b))
        }

        samples.sort { $0.luma > $1.luma }
        let count = max(1, samples.count / 5)
        let brightest = samples.prefix(count)
        let scale = 1 / CGFloat(count)

        return (
            r: brightest.reduce(0) { $0 + $1.r } * scale,
            g: brightest.reduce(0) { $0 + $1.g } * scale,
            b: brightest.reduce(0) { $0 + $1.b } * scale
        )
    }

    private func linearSRGB(_ value: CGFloat) -> CGFloat {
        if value <= 0.04045 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }

    private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.min(upper, Swift.max(lower, value))
    }

}
