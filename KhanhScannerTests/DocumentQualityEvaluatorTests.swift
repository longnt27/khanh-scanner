import XCTest
import UIKit
@testable import KhanhScanner

final class DocumentQualityEvaluatorTests: XCTestCase {
    func testFlatScannedPageIsAccepted() {
        XCTAssertEqual(
            ScannedPageQualityValidator.quality(of: pageImage(foldedCorner: false)),
            .ready
        )
    }

    func testObviousFoldedCornerIsRejected() {
        XCTAssertEqual(
            ScannedPageQualityValidator.quality(of: pageImage(foldedCorner: true)),
            .flattenCorners
        )
    }

    func testPrintedDiagonalLineIsNotMistakenForFoldedPaper() {
        let image = pageImage(foldedCorner: false, diagonalLine: true)

        XCTAssertEqual(ScannedPageQualityValidator.quality(of: image), .ready)
    }

    func testValidationKeepsGoodPagesAndCountsRejectedPages() {
        let pages = [pageImage(foldedCorner: false), pageImage(foldedCorner: false)]
        var index = 0

        let result = ScannedPageQualityValidator.validate(pages) { _ in
            defer { index += 1 }
            return index == 0 ? .ready : .flattenCorners
        }

        XCTAssertEqual(result.acceptedPages.count, 1)
        XCTAssertEqual(result.rejectedPageCount, 1)
    }

    func testWarningUsesRequiredInstruction() {
        XCTAssertEqual(
            ScannedPageQualityValidator.warningMessage,
            "Flatten all four corners before scanning."
        )
    }

    private func pageImage(foldedCorner: Bool, diagonalLine: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 340), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 340))

            UIColor.black.setFill()
            for row in 0..<7 {
                context.fill(CGRect(x: 45, y: 90 + row * 24, width: 165, height: 3))
            }

            if foldedCorner {
                let fold = UIBezierPath()
                fold.move(to: .zero)
                fold.addLine(to: CGPoint(x: 70, y: 0))
                fold.addLine(to: CGPoint(x: 0, y: 70))
                fold.close()
                UIColor(white: 0.12, alpha: 1).setFill()
                fold.fill()
            }

            if diagonalLine {
                let line = UIBezierPath()
                line.move(to: CGPoint(x: 10, y: 55))
                line.addLine(to: CGPoint(x: 55, y: 10))
                line.lineWidth = 3
                UIColor.black.setStroke()
                line.stroke()
            }
        }
    }
}
