import CoreImage
import UIKit

final class DocumentEnhancer {
    enum EnhancementError: Error { case invalidImage, renderFailed }
    private static let context = CIContext(options: [.cacheIntermediates: true])

    func enhance(_ image: UIImage) throws -> UIImage {
        guard let cg = image.cgImage else { throw EnhancementError.invalidImage }
        let input = CIImage(cgImage: cg)

        // Push light paper toward white and dark text toward black without
        // removing saturation. This intentionally avoids grayscale/monochrome
        // filters so signatures, stamps and highlights retain their hue.
        let controls = CIFilter(name: "CIColorControls")
        controls?.setValue(input, forKey: kCIInputImageKey)
        controls?.setValue(1.18, forKey: kCIInputContrastKey)
        controls?.setValue(0.08, forKey: kCIInputBrightnessKey)
        controls?.setValue(1.08, forKey: kCIInputSaturationKey)

        guard let output = controls?.outputImage,
              let rendered = Self.context.createCGImage(output, from: input.extent) else {
            throw EnhancementError.renderFailed
        }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: .up)
    }
}
