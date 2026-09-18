import CoreGraphics
import Foundation
import simd

struct ScannerV2Quadrilateral: Equatable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    var points: [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    var center: CGPoint {
        CGPoint(
            x: points.reduce(0) { $0 + $1.x } / 4,
            y: points.reduce(0) { $0 + $1.y } / 4
        )
    }
}

enum ScannerV2PlaneGeometry {
    static func intersection(
        rayOrigin: SIMD3<Float>,
        rayDirection: SIMD3<Float>,
        planePoint: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> SIMD3<Float>? {
        let denominator = simd_dot(planeNormal, rayDirection)
        guard abs(denominator) > 0.000_01 else { return nil }

        let distance = simd_dot(planePoint - rayOrigin, planeNormal) / denominator
        guard distance >= 0 else { return nil }
        return rayOrigin + rayDirection * distance
    }

    static func rectangleScore(_ points: [SIMD2<Float>]) -> Float {
        guard points.count == 4 else { return 0 }

        let edges = points.indices.map { index in
            points[(index + 1) % 4] - points[index]
        }
        let lengths = edges.map(simd_length)
        guard let shortest = lengths.min(), shortest > 0.000_01 else { return 0 }

        let perpendicularScores = points.indices.map { index -> Float in
            let first = simd_normalize(edges[index])
            let second = simd_normalize(edges[(index + 1) % 4])
            return max(0, 1 - abs(simd_dot(first, second)))
        }

        let parallelA = abs(simd_dot(simd_normalize(edges[0]), simd_normalize(edges[2])))
        let parallelB = abs(simd_dot(simd_normalize(edges[1]), simd_normalize(edges[3])))
        let oppositeLengthA = ratioScore(lengths[0], lengths[2])
        let oppositeLengthB = ratioScore(lengths[1], lengths[3])

        let diagonalA = simd_length(points[2] - points[0])
        let diagonalB = simd_length(points[3] - points[1])
        let diagonalScore = ratioScore(diagonalA, diagonalB)

        let angleScore = perpendicularScores.reduce(0, +) / 4
        let parallelScore = (parallelA + parallelB) / 2
        let lengthScore = (oppositeLengthA + oppositeLengthB) / 2

        return clamp(
            angleScore * 0.45
                + parallelScore * 0.20
                + lengthScore * 0.20
                + diagonalScore * 0.15
        )
    }

    static func planeCoordinates(
        worldPoints: [SIMD3<Float>],
        planeTransform: simd_float4x4
    ) -> [SIMD2<Float>] {
        let inverse = simd_inverse(planeTransform)
        return worldPoints.map { point in
            let local = inverse * SIMD4<Float>(point.x, point.y, point.z, 1)
            return SIMD2<Float>(local.x, local.z)
        }
    }

    private static func ratioScore(_ first: Float, _ second: Float) -> Float {
        let hi = max(first, second)
        guard hi > 0.000_01 else { return 0 }
        return min(first, second) / hi
    }

    private static func clamp(_ value: Float) -> Float {
        min(1, max(0, value))
    }
}

struct ScannerV2StabilityTracker {
    private let requiredSamples: Int
    private let maximumCornerDrift: CGFloat
    private var samples: [ScannerV2Quadrilateral] = []

    init(requiredSamples: Int = 5, maximumCornerDrift: CGFloat = 0.012) {
        self.requiredSamples = max(2, requiredSamples)
        self.maximumCornerDrift = maximumCornerDrift
    }

    var sampleCount: Int { samples.count }

    mutating func reset() {
        samples.removeAll()
    }

    mutating func append(_ quadrilateral: ScannerV2Quadrilateral) -> Bool {
        if let last = samples.last,
           maximumDistance(last, quadrilateral) > maximumCornerDrift {
            samples = [quadrilateral]
            return false
        }

        samples.append(quadrilateral)
        if samples.count > requiredSamples {
            samples.removeFirst(samples.count - requiredSamples)
        }
        return samples.count >= requiredSamples
    }

    private func maximumDistance(
        _ first: ScannerV2Quadrilateral,
        _ second: ScannerV2Quadrilateral
    ) -> CGFloat {
        zip(first.points, second.points)
            .map { hypot($0.x - $1.x, $0.y - $1.y) }
            .max() ?? .greatestFiniteMagnitude
    }
}

enum ScannerV2CaptureState: Equatable {
    case findDocument
    case holdSteady
    case focusing
    case alignDocument
    case tooBlurry
    case ready

    var instruction: String {
        switch self {
        case .findDocument: "Point the camera at a document."
        case .holdSteady: "Hold steady."
        case .focusing: "Focusing…"
        case .alignDocument: "Keep the full document flat and visible."
        case .tooBlurry: "Hold steady for a sharper scan."
        case .ready: "Ready"
        }
    }
}

enum ScannerV2CaptureGate {
    static func evaluate(
        hasDocument: Bool,
        documentStable: Bool,
        cameraStable: Bool,
        planeScore: Float,
        planeAvailable: Bool,
        focusAdjusting: Bool,
        exposureAdjusting: Bool,
        sharpnessScore: Float
    ) -> ScannerV2CaptureState {
        guard hasDocument else { return .findDocument }
        guard cameraStable, documentStable else { return .holdSteady }
        guard !focusAdjusting, !exposureAdjusting else { return .focusing }
        if planeAvailable && planeScore < 0.78 {
            return .alignDocument
        }
        guard sharpnessScore >= 0.35 else { return .tooBlurry }
        return .ready
    }
}
