import UIKit

enum DocumentPageRendererError: LocalizedError {
    case invalidCrop
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .invalidCrop:
            "The selected crop is not a valid document shape."
        case .renderFailed:
            "The page could not be rendered."
        }
    }
}

enum DocumentPageRenderer {
    static func render(
        source: UIImage,
        page: DocumentPage,
        enhance: Bool
    ) throws -> UIImage {
        guard page.cropQuadrilateral.isValidCrop else {
            throw DocumentPageRendererError.invalidCrop
        }

        guard let corrected = ScannerV2ImageProcessor.manualPerspectiveCrop(
            from: source,
            quadrilateral: page.cropQuadrilateral
        ) else {
            throw DocumentPageRendererError.renderFailed
        }

        let cleaned = ScannerV2ImageProcessor.trimBackgroundSlivers(from: corrected) ?? corrected
        guard let rotated = rotated(cleaned, rotation: page.rotation) else {
            throw DocumentPageRendererError.renderFailed
        }

        if enhance {
            return try DocumentEnhancer().enhance(rotated)
        }
        return rotated
    }

    private static func rotated(
        _ image: UIImage,
        rotation: DocumentPageRotation
    ) -> UIImage? {
        guard rotation != .none else { return image }

        let quarterTurns: Int
        switch rotation {
        case .none: quarterTurns = 0
        case .clockwise90: quarterTurns = 1
        case .clockwise180: quarterTurns = 2
        case .clockwise270: quarterTurns = 3
        }

        let swapsDimensions = quarterTurns % 2 == 1
        let size = swapsDimensions
            ? CGSize(width: image.size.height, height: image.size.width)
            : image.size

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: CGFloat(quarterTurns) * .pi / 2)

            let drawSize = image.size
            image.draw(
                in: CGRect(
                    x: -drawSize.width / 2,
                    y: -drawSize.height / 2,
                    width: drawSize.width,
                    height: drawSize.height
                )
            )
        }
    }
}
