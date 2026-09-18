import UIKit

enum DocumentPageRotation: Int, Codable, CaseIterable {
    case none = 0
    case clockwise90 = 90
    case clockwise180 = 180
    case clockwise270 = 270

    func rotated(clockwise: Bool) -> DocumentPageRotation {
        let delta = clockwise ? 90 : -90
        let normalized = (rawValue + delta + 360) % 360
        return DocumentPageRotation(rawValue: normalized) ?? .none
    }
}

struct DocumentPage: Codable, Identifiable, Equatable {
    let id: UUID
    var cropQuadrilateral: ScannerV2Quadrilateral
    var rotation: DocumentPageRotation
    var isLegacySource: Bool

    init(
        id: UUID = UUID(),
        cropQuadrilateral: ScannerV2Quadrilateral = .fullBounds,
        rotation: DocumentPageRotation = .none,
        isLegacySource: Bool = false
    ) {
        self.id = id
        self.cropQuadrilateral = cropQuadrilateral
        self.rotation = rotation
        self.isLegacySource = isLegacySource
    }
}

struct DocumentPageAssets {
    var page: DocumentPage
    var sourceImage: UIImage
    var renderedImage: UIImage
}
