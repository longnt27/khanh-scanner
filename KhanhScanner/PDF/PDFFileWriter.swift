import Foundation

enum PDFFileWriter {
    static func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Khanh-Scan-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
