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


enum ScannerV2ViewportMapper {
    static func viewPoint(
        for visionPoint: CGPoint,
        orientedImageSize: CGSize,
        viewportSize: CGSize
    ) -> CGPoint {
        guard orientedImageSize.width > 0,
              orientedImageSize.height > 0,
              viewportSize.width > 0,
              viewportSize.height > 0 else {
            return .zero
        }

        let scale = max(
            viewportSize.width / orientedImageSize.width,
            viewportSize.height / orientedImageSize.height
        )
        let renderedSize = CGSize(
            width: orientedImageSize.width * scale,
            height: orientedImageSize.height * scale
        )
        let origin = CGPoint(
            x: (viewportSize.width - renderedSize.width) / 2,
            y: (viewportSize.height - renderedSize.height) / 2
        )

        return CGPoint(
            x: origin.x + visionPoint.x * renderedSize.width,
            y: origin.y + (1 - visionPoint.y) * renderedSize.height
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
        guard distance > 0 else { return nil }
        return rayOrigin + rayDirection * distance
    }

    static func fittedRectangle(_ points: [SIMD2<Float>]) -> [SIMD2<Float>]? {
        guard points.count == 4 else { return nil }

        let top = points[1] - points[0]
        let bottom = points[2] - points[3]
        let leftUp = points[0] - points[3]
        let rightUp = points[1] - points[2]

        let horizontalSeed = top + bottom
        let verticalSeed = leftUp + rightUp
        guard simd_length(horizontalSeed) > 0.000_1,
              simd_length(verticalSeed) > 0.000_1 else {
            return nil
        }

        let horizontal = simd_normalize(horizontalSeed)
        var vertical = verticalSeed - horizontal * simd_dot(verticalSeed, horizontal)
        guard simd_length(vertical) > 0.000_1 else { return nil }
        vertical = simd_normalize(vertical)
        if simd_dot(vertical, verticalSeed) < 0 {
            vertical = -vertical
        }

        let center = points.reduce(SIMD2<Float>(repeating: 0), +) / 4
        let offsets = points.map { $0 - center }
        let halfWidth = offsets.map { abs(simd_dot($0, horizontal)) }.reduce(0, +) / 4
        let halfHeight = offsets.map { abs(simd_dot($0, vertical)) }.reduce(0, +) / 4
        guard halfWidth > 0.000_1, halfHeight > 0.000_1 else { return nil }

        return [
            center - horizontal * halfWidth + vertical * halfHeight,
            center + horizontal * halfWidth + vertical * halfHeight,
            center + horizontal * halfWidth - vertical * halfHeight,
            center - horizontal * halfWidth - vertical * halfHeight
        ]
    }

    static func regularizedWorldRectangle(
        _ worldPoints: [SIMD3<Float>],
        planeTransform: simd_float4x4
    ) -> [SIMD3<Float>]? {
        guard worldPoints.count == 4 else { return nil }

        let inverse = simd_inverse(planeTransform)
        let localPoints = worldPoints.map { point -> SIMD2<Float> in
            let local = inverse * SIMD4<Float>(point.x, point.y, point.z, 1)
            return SIMD2<Float>(local.x, local.z)
        }
        guard let fitted = fittedRectangle(localPoints) else { return nil }

        return fitted.map { point -> SIMD3<Float> in
            let world = planeTransform * SIMD4<Float>(point.x, 0, point.y, 1)
            return SIMD3<Float>(world.x, world.y, world.z)
        }
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
    case captured

    var statusText: String {
        switch self {
        case .noDocument:
            "Find a document"
        case .holdSteady:
            "Hold steady"
        case .alignDocument:
            "Align the page"
        case .waitForCamera:
            "Focusing…"
        case .tooSoft:
            "Hold steady for a sharper scan"
        case .ready:
            "Ready"
        case .captured:
            "Captured — move to next page"
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

struct ScannerV2AutoCaptureRearmGate {
    let requiredMissingFrames: Int
    private(set) var isArmed = true
    private var consecutiveMissingFrames = 0

    init(requiredMissingFrames: Int = 8) {
        self.requiredMissingFrames = max(1, requiredMissingFrames)
    }

    mutating func markCaptured() {
        isArmed = false
        consecutiveMissingFrames = 0
    }

    mutating func observeDocument(present: Bool) {
        guard !isArmed else { return }

        if present {
            consecutiveMissingFrames = 0
            return
        }

        consecutiveMissingFrames += 1
        if consecutiveMissingFrames >= requiredMissingFrames {
            isArmed = true
            consecutiveMissingFrames = 0
        }
    }
}

struct ScannerV2PageChangeDetector {
    let minimumChange: CGFloat
    let minimumContentChange: Float

    private var capturedQuadrilateral: ScannerV2Quadrilateral?
    private var capturedFingerprint: ScannerV2PageFingerprint?

    init(
        minimumChange: CGFloat = 0.05,
        minimumContentChange: Float = 0.12
    ) {
        self.minimumChange = minimumChange
        self.minimumContentChange = minimumContentChange
    }

    mutating func markCaptured(
        _ quadrilateral: ScannerV2Quadrilateral,
        fingerprint: ScannerV2PageFingerprint? = nil
    ) {
        capturedQuadrilateral = quadrilateral
        capturedFingerprint = fingerprint
    }

    func canCapture(
        _ quadrilateral: ScannerV2Quadrilateral,
        fingerprint: ScannerV2PageFingerprint? = nil
    ) -> Bool {
        guard let capturedQuadrilateral else { return true }

        if capturedQuadrilateral.maximumCornerDistance(to: quadrilateral) >= minimumChange {
            return true
        }

        guard let capturedFingerprint, let fingerprint else {
            return false
        }
        return capturedFingerprint.distance(to: fingerprint) >= minimumContentChange
    }

    mutating func reset() {
        capturedQuadrilateral = nil
        capturedFingerprint = nil
    }
}
