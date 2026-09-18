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

    func maximumCornerDistance(to other: ScannerV2Quadrilateral) -> CGFloat {
        zip(points, other.points)
            .map { hypot($0.x - $1.x, $0.y - $1.y) }
            .max() ?? 0
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
        guard distance > 0 else { return nil }
        return rayOrigin + rayDirection * distance
    }

    static func rectangleScore(_ points: [SIMD2<Float>]) -> Float {
        guard points.count == 4 else { return 0 }

        let edges = points.indices.map { index in
            points[(index + 1) % points.count] - points[index]
        }
        let lengths = edges.map(simd_length)
        guard lengths.allSatisfy({ $0 > 0.000_1 }) else { return 0 }

        let normalized = edges.map(simd_normalize)
        let orthogonality = normalized.indices.map { index -> Float in
            let next = normalized[(index + 1) % normalized.count]
            return 1 - min(1, abs(simd_dot(normalized[index], next)))
        }.min() ?? 0

        let parallelism = min(
            abs(simd_dot(normalized[0], normalized[2])),
            abs(simd_dot(normalized[1], normalized[3]))
        )

        let oppositeLengthSimilarity = min(
            min(lengths[0], lengths[2]) / max(lengths[0], lengths[2]),
            min(lengths[1], lengths[3]) / max(lengths[1], lengths[3])
        )

        let crossProducts = edges.indices.map { index -> Float in
            let current = edges[index]
            let next = edges[(index + 1) % edges.count]
            return current.x * next.y - current.y * next.x
        }
        let hasConsistentWinding = crossProducts.allSatisfy { $0 > 0 }
            || crossProducts.allSatisfy { $0 < 0 }

        guard hasConsistentWinding else { return 0 }

        return max(0, min(1, min(orthogonality, parallelism, oppositeLengthSimilarity)))
    }
    static func rectangleScore3D(_ points: [SIMD3<Float>]) -> Float {
        guard points.count == 4 else { return 0 }
        let edges = points.indices.map { index in
            points[(index + 1) % points.count] - points[index]
        }
        let lengths = edges.map(simd_length)
        guard lengths.allSatisfy({ $0 > 0.000_1 }) else { return 0 }

        let normalized = edges.map(simd_normalize)
        let orthogonality = normalized.indices.map { index -> Float in
            let next = normalized[(index + 1) % normalized.count]
            return 1 - min(1, abs(simd_dot(normalized[index], next)))
        }.min() ?? 0

        let parallelism = min(
            abs(simd_dot(normalized[0], normalized[2])),
            abs(simd_dot(normalized[1], normalized[3]))
        )
        let oppositeLengthSimilarity = min(
            min(lengths[0], lengths[2]) / max(lengths[0], lengths[2]),
            min(lengths[1], lengths[3]) / max(lengths[1], lengths[3])
        )

        return max(0, min(1, min(orthogonality, parallelism, oppositeLengthSimilarity)))
    }
}

struct ScannerV2StabilityTracker {
    let requiredSamples: Int
    let maximumCornerDrift: CGFloat
    private(set) var samples: [ScannerV2Quadrilateral] = []

    init(requiredSamples: Int = 6, maximumCornerDrift: CGFloat = 0.012) {
        self.requiredSamples = max(1, requiredSamples)
        self.maximumCornerDrift = maximumCornerDrift
    }

    var sampleCount: Int { samples.count }

    mutating func append(_ quadrilateral: ScannerV2Quadrilateral) -> Bool {
        if let previous = samples.last,
           previous.maximumCornerDistance(to: quadrilateral) > maximumCornerDrift {
            samples = [quadrilateral]
            return requiredSamples == 1
        }

        samples.append(quadrilateral)
        if samples.count > requiredSamples {
            samples.removeFirst(samples.count - requiredSamples)
        }
        return samples.count >= requiredSamples
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }
}

enum ScannerV2CaptureReadiness: Equatable {
    case noDocument
    case holdSteady
    case alignDocument
    case waitForCamera
    case tooSoft
    case ready
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
    ) -> ScannerV2CaptureReadiness {
        guard hasDocument else { return .noDocument }
        guard cameraStable, documentStable else { return .holdSteady }

        if planeAvailable, planeScore < 0.82 {
            return .alignDocument
        }

        if focusAdjusting || exposureAdjusting {
            return .waitForCamera
        }

        guard sharpnessScore >= 0.25 else {
            return .tooSoft
        }

        return .ready
    }
}


struct ScannerV2CameraMotionTracker {
    let requiredSamples: Int
    let maximumTranslationDelta: Float
    let maximumRotationDelta: Float

    private var previousTransform: simd_float4x4?
    private(set) var sampleCount: Int = 0

    init(
        requiredSamples: Int = 5,
        maximumTranslationDelta: Float = 0.012,
        maximumRotationDelta: Float = 0.035
    ) {
        self.requiredSamples = max(1, requiredSamples)
        self.maximumTranslationDelta = maximumTranslationDelta
        self.maximumRotationDelta = maximumRotationDelta
    }

    mutating func append(_ transform: simd_float4x4) -> Bool {
        guard let previousTransform else {
            self.previousTransform = transform
            sampleCount = 1
            return requiredSamples == 1
        }

        let previousPosition = SIMD3<Float>(
            previousTransform.columns.3.x,
            previousTransform.columns.3.y,
            previousTransform.columns.3.z
        )
        let position = SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
        let translationDelta = simd_distance(previousPosition, position)

        let previousRotation = simd_float3x3(
            SIMD3<Float>(previousTransform.columns.0.x, previousTransform.columns.0.y, previousTransform.columns.0.z),
            SIMD3<Float>(previousTransform.columns.1.x, previousTransform.columns.1.y, previousTransform.columns.1.z),
            SIMD3<Float>(previousTransform.columns.2.x, previousTransform.columns.2.y, previousTransform.columns.2.z)
        )
        let rotation = simd_float3x3(
            SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        )
        let relativeRotation = simd_transpose(previousRotation) * rotation
        let trace = relativeRotation.columns.0.x
            + relativeRotation.columns.1.y
            + relativeRotation.columns.2.z
        let cosine = max(-1, min(1, (trace - 1) / 2))
        let rotationDelta = acos(cosine)

        self.previousTransform = transform

        if translationDelta > maximumTranslationDelta || rotationDelta > maximumRotationDelta {
            sampleCount = 1
            return requiredSamples == 1
        }

        sampleCount = min(requiredSamples, sampleCount + 1)
        return sampleCount >= requiredSamples
    }

    mutating func reset() {
        previousTransform = nil
        sampleCount = 0
    }
}

struct ScannerV2PageChangeDetector {
    let minimumChange: CGFloat
    private var capturedQuadrilateral: ScannerV2Quadrilateral?

    init(minimumChange: CGFloat = 0.05) {
        self.minimumChange = minimumChange
    }

    mutating func markCaptured(_ quadrilateral: ScannerV2Quadrilateral) {
        capturedQuadrilateral = quadrilateral
    }

    func canCapture(_ quadrilateral: ScannerV2Quadrilateral) -> Bool {
        guard let capturedQuadrilateral else { return true }
        return capturedQuadrilateral.maximumCornerDistance(to: quadrilateral) >= minimumChange
    }

    mutating func reset() {
        capturedQuadrilateral = nil
    }
}
