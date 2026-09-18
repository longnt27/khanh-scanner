import CoreImage
import ImageIO
import UIKit
import Vision

enum DocumentRectangleProcessor {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func observation(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) throws -> VNRectangleObservation? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        try handler.perform([request])
        return request.results?.first
    }

    static func observation(in image: CGImage) throws -> VNRectangleObservation? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])
        return request.results?.first
    }

    static func quadrilateral(from observation: VNRectangleObservation) -> DocumentQuadrilateral {
        DocumentQuadrilateral(
            topLeft: observation.topLeft,
            topRight: observation.topRight,
            bottomRight: observation.bottomRight,
            bottomLeft: observation.bottomLeft
        )
    }

    static func correctedImage(
        from image: CGImage,
        quadrilateral: DocumentQuadrilateral
    ) -> UIImage? {
        let input = CIImage(cgImage: image)
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(vector(quadrilateral.topLeft, width: width, height: height), forKey: "inputTopLeft")
        filter.setValue(vector(quadrilateral.topRight, width: width, height: height), forKey: "inputTopRight")
        filter.setValue(vector(quadrilateral.bottomRight, width: width, height: height), forKey: "inputBottomRight")
        filter.setValue(vector(quadrilateral.bottomLeft, width: width, height: height), forKey: "inputBottomLeft")
        guard let output = filter.outputImage,
              !output.extent.isEmpty,
              let corrected = context.createCGImage(output, from: output.extent) else {
            return nil
        }
        return UIImage(cgImage: corrected)
    }

    private static func vector(_ point: CGPoint, width: CGFloat, height: CGFloat) -> CIVector {
        CIVector(x: point.x * width, y: point.y * height)
    }
}
