import Foundation

enum PDFFileWriter {
    static func write(_ data: Data, suggestedName: String = "Document") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KhanhScannerExport-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = sanitizedFilename(suggestedName)
        let url = directory
            .appendingPathComponent(filename)
            .appendingPathExtension("pdf")

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func sanitizedFilename(_ rawName: String) -> String {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: "/", with: " - ")
        name = name.replacingOccurrences(of: "\\", with: " - ")

        for character in [":", "*", "?", "\"", "<", ">", "|"] {
            name = name.replacingOccurrences(of: character, with: "-")
        }

        name = name
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        return name.isEmpty ? "Document" : name
    }
}
