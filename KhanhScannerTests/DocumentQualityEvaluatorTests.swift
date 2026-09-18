import XCTest
import UIKit
@testable import KhanhScanner

final class DocumentQualityEvaluatorTests: XCTestCase {
    func testFlatDocumentIsReady() {
        let rectangle = DocumentQuadrilateral(
            topLeft: CGPoint(x: 0.1, y: 0.9),
            topRight: CGPoint(x: 0.9, y: 0.9),
            bottomRight: CGPoint(x: 0.9, y: 0.1),
            bottomLeft: CGPoint(x: 0.1, y: 0.1)
        )

        XCTAssertEqual(DocumentQualityEvaluator.evaluate(rectangle, confidence: 0.95), .ready)
    }

    func testNormalPerspectiveDocumentIsReady() {
        let rectangle = DocumentQuadrilateral(
            topLeft: CGPoint(x: 0.20, y: 0.90),
            topRight: CGPoint(x: 0.78, y: 0.84),
            bottomRight: CGPoint(x: 0.93, y: 0.10),
            bottomLeft: CGPoint(x: 0.07, y: 0.16)
        )

        XCTAssertEqual(DocumentQualityEvaluator.evaluate(rectangle, confidence: 0.90), .ready)
    }

    func testClearlyFoldedCornerGeometryIsRejected() {
        let rectangle = DocumentQuadrilateral(
            topLeft: CGPoint(x: 0.74, y: 0.80),
            topRight: CGPoint(x: 0.90, y: 0.90),
            bottomRight: CGPoint(x: 0.90, y: 0.10),
            bottomLeft: CGPoint(x: 0.10, y: 0.10)
        )

        XCTAssertEqual(DocumentQualityEvaluator.evaluate(rectangle, confidence: 0.90), .flattenCorners)
    }

    func testWeakRectangleConfidenceIsRejectedConservatively() {
        let rectangle = DocumentQuadrilateral(
            topLeft: CGPoint(x: 0.1, y: 0.9),
            topRight: CGPoint(x: 0.9, y: 0.9),
            bottomRight: CGPoint(x: 0.9, y: 0.1),
            bottomLeft: CGPoint(x: 0.1, y: 0.1)
        )

        XCTAssertEqual(DocumentQualityEvaluator.evaluate(rectangle, confidence: 0.35), .flattenCorners)
    }

    func testMissingEdgeSupportNearACornerIsRejected() {
        let rectangle = DocumentQuadrilateral(
            topLeft: CGPoint(x: 0.1, y: 0.9),
            topRight: CGPoint(x: 0.9, y: 0.9),
            bottomRight: CGPoint(x: 0.9, y: 0.1),
            bottomLeft: CGPoint(x: 0.1, y: 0.1)
        )
        let support = DocumentEdgeSupport(overall: 0.82, weakestEnd: 0.18)

        XCTAssertEqual(
            DocumentQualityEvaluator.evaluate(rectangle, confidence: 0.90, edgeSupport: support),
            .flattenCorners
        )
    }

    func testEdgeAnalyzerFindsAContinuouslySupportedRectangle() {
        let support = DocumentEdgeAnalyzer.measure(in: pageImage(foldedCorner: false), quadrilateral: fullPage)

        XCTAssertGreaterThan(support.overall, 0.80)
        XCTAssertGreaterThan(support.weakestEnd, 0.70)
    }

    func testEdgeAnalyzerFindsMissingSupportAtAFoldedCorner() {
        let support = DocumentEdgeAnalyzer.measure(in: pageImage(foldedCorner: true), quadrilateral: fullPage)

        XCTAssertLessThan(support.weakestEnd, 0.32)
    }

    func testPerspectiveCorrectionProducesACroppedPage() throws {
        let corrected = try XCTUnwrap(
            DocumentRectangleProcessor.correctedImage(from: pageImage(foldedCorner: false), quadrilateral: fullPage)
        )

        XCTAssertGreaterThan(corrected.size.width, 150)
        XCTAssertGreaterThan(corrected.size.height, 150)
    }

    private var fullPage: DocumentQuadrilateral {
        DocumentQuadrilateral(
            topLeft: CGPoint(x: 0.10, y: 0.90),
            topRight: CGPoint(x: 0.90, y: 0.90),
            bottomRight: CGPoint(x: 0.90, y: 0.10),
            bottomLeft: CGPoint(x: 0.10, y: 0.10)
        )
    }

    private func pageImage(foldedCorner: Bool) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor.white.setFill()
            if foldedCorner {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 78, y: 26))
                path.addLine(to: CGPoint(x: 230, y: 26))
                path.addLine(to: CGPoint(x: 230, y: 230))
                path.addLine(to: CGPoint(x: 26, y: 230))
                path.addLine(to: CGPoint(x: 26, y: 78))
                path.close()
                path.fill()
            } else {
                context.fill(CGRect(x: 26, y: 26, width: 204, height: 204))
            }
        }
        return image.cgImage!
    }
}
