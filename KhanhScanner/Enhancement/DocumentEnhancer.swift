import CoreImage
import UIKit

final class DocumentEnhancer {
    enum EnhancementError: Error { case invalidImage, renderFailed }

    private static let context = CIContext(options: [.cacheIntermediates: true])
    private static let paperCubeDimension = 24
    private static let paperCubeData: Data = {
        let dimension = paperCubeDimension
        var values = [Float]()
        values.reserveCapacity(dimension * dimension * dimension * 4)

        for blue in 0..<dimension {
            let b = Float(blue) / Float(dimension - 1)
            for green in 0..<dimension {
                let g = Float(green) / Float(dimension - 1)
                for red in 0..<dimension {
                    let r = Float(red) / Float(dimension - 1)

                    let hi = max(r, g, b)
                    let lo = min(r, g, b)
                    let saturation = hi > 0.0001 ? (hi - lo) / hi : 0
                    let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

                    // Paper is generally one of the brighter, less-saturated
                    // surfaces in a scan. Use soft transitions so pale stamps
                    // and highlights do not hit a hard threshold.
                    let bright = smoothstep(0.52, 0.82, luminance)
                    let lowSaturation = 1 - smoothstep(0.18, 0.55, saturation)
                    let paperWeight = bright * lowSaturation

                    let neutral = min(1, luminance + (1 - luminance) * 0.65)
                    values.append(mix(r, neutral, paperWeight))
                    values.append(mix(g, neutral, paperWeight))
                    values.append(mix(b, neutral, paperWeight))
                    values.append(1)
                }
            }
        }

        return values.withUnsafeBytes { Data($0) }
    }()

    func enhance(_ image: UIImage) throws -> UIImage {
        guard let cg = image.cgImage else { throw EnhancementError.invalidImage }
        let input = CIImage(cgImage: cg)

        let neutralized = neutralizePaper(in: input)

        // After neutralizing paper-like pixels, add moderate contrast while
        // retaining chromatic content such as signatures, stamps and marks.
        let controls = CIFilter(name: "CIColorControls")
        controls?.setValue(neutralized, forKey: kCIInputImageKey)
        controls?.setValue(1.18, forKey: kCIInputContrastKey)
        controls?.setValue(0.05, forKey: kCIInputBrightnessKey)
        controls?.setValue(1.05, forKey: kCIInputSaturationKey)

        guard let output = controls?.outputImage,
              let rendered = Self.context.createCGImage(output, from: input.extent) else {
            throw EnhancementError.renderFailed
        }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: .up)
    }

    private func neutralizePaper(in image: CIImage) -> CIImage {
        guard let cube = CIFilter(name: "CIColorCube") else { return image }
        cube.setValue(image, forKey: kCIInputImageKey)
        cube.setValue(Self.paperCubeDimension, forKey: "inputCubeDimension")
        cube.setValue(Self.paperCubeData, forKey: "inputCubeData")
        return cube.outputImage ?? image
    }

    private static func smoothstep(_ lower: Float, _ upper: Float, _ value: Float) -> Float {
        guard upper > lower else { return value >= upper ? 1 : 0 }
        let t = min(1, max(0, (value - lower) / (upper - lower)))
        return t * t * (3 - 2 * t)
    }

    private static func mix(_ from: Float, _ to: Float, _ amount: Float) -> Float {
        from + (to - from) * amount
    }
}
