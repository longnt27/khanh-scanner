import XCTest
import PDFKit
import UIKit
@testable import KhanhScanner

final class PDFExporterTests: XCTestCase {
    func testRejectsEmptyInput() {
        XCTAssertThrowsError(try PDFExporter.makePDF(from: []))
    }

    func testPageCountMatchesImages() throws {
        let data = try PDFExporter.makePDF(from: [image(width: 300, height: 500), image(width: 300, height: 500)])
        let document = PDFDocument(data: data)
        XCTAssertEqual(document?.pageCount, 2)
    }

    func testExportsMixedOrientations() throws {
        let data = try PDFExporter.makePDF(from: [image(width: 300, height: 500), image(width: 500, height: 300)])
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, 2)
        let first = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        let second = try XCTUnwrap(document.page(at: 1)).bounds(for: .mediaBox)
        XCTAssertGreaterThan(first.height, first.width)
        XCTAssertGreaterThan(second.width, second.height)
    }

    func testPDFFileWriterUsesSanitizedDocumentName() throws {
        let url = try PDFFileWriter.write(
            Data("pdf".utf8),
            suggestedName: "  Client / Contract: 2026  "
        )
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        XCTAssertEqual(url.lastPathComponent, "Client - Contract- 2026.pdf")
    }

    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
