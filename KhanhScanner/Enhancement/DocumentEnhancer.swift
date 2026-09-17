import CoreImage
import UIKit

final class DocumentEnhancer {
    enum EnhancementError: Error { case invalidImage, renderFailed }
    private static let context = CIContext(options: [.cacheIntermediates: true])
    private static let kernel = CIColorKernel(source: """
        kernel vec4 enhance(__sample p) {
            float hi = max(p.r, max(p.g, p.b));
            float lo = min(p.r, min(p.g, p.b));
            float chroma = hi - lo;
            float y = dot(p.rgb, vec3(0.2126, 0.7152, 0.0722));
            float neutral = smoothstep(0.08, 0.18, chroma);
            float mono = smoothstep(0.28, 0.78, y);
            mono = clamp((mono - 0.5) * 1.35 + 0.5, 0.0, 1.0);
            vec3 neutralRGB = vec3(mono);
            vec3 colorRGB = clamp((p.rgb - vec3(0.5)) * 1.10 + vec3(0.54), 0.0, 1.0);
            return vec4(mix(neutralRGB, colorRGB, neutral), p.a);
        }
    """)!

    func enhance(_ image: UIImage) throws -> UIImage {
        guard let cg = image.cgImage else { throw EnhancementError.invalidImage }
        let input = CIImage(cgImage: cg)
        guard let output = Self.kernel.apply(extent: input.extent, arguments: [input]),
              let rendered = Self.context.createCGImage(output, from: output.extent) else {
            throw EnhancementError.renderFailed
        }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: .up)
    }
}
