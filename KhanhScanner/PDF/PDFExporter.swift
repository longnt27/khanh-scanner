import UIKit

enum PDFExporterError: Error { case noPages }

enum PDFExporter {
    static func makePDF(from images: [UIImage]) throws -> Data {
        guard !images.isEmpty else { throw PDFExporterError.noPages }
        let a4 = CGSize(width: 595.28, height: 841.89)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: a4))
        return renderer.pdfData { context in
            for image in images {
                let landscape = image.size.width > image.size.height
                let size = landscape ? CGSize(width: a4.height, height: a4.width) : a4
                let bounds = CGRect(origin: .zero, size: size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                UIColor.white.setFill()
                context.cgContext.fill(bounds)
                let scale = min(size.width / image.size.width, size.height / image.size.height)
                let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let rect = CGRect(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2, width: drawSize.width, height: drawSize.height)
                image.draw(in: rect)
            }
        }
    }
}
