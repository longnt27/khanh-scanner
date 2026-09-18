import XCTest
import simd
@testable import KhanhScanner

final class ScannerV2GeometryTests: XCTestCase {
    func testRayPlaneIntersectionFindsExpectedPoint() throws {
        let planePoint = SIMD3<Float>(0, 0, 0)
        let planeNormal = SIMD3<Float>(0, 1, 0)
        let rayOrigin = SIMD3<Float>(0.4, 1, -0.2)
        let rayDirection = simd_normalize(SIMD3<Float>(0, -1, 0))

        let point = try XCTUnwrap(
            ScannerV2PlaneGeometry.intersection(
                rayOrigin: rayOrigin,
                rayDirection: rayDirection,
                planePoint: planePoint,
                planeNormal: planeNormal
            )
        )

        XCTAssertEqual(point.x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(point.y, 0, accuracy: 0.0001)
        XCTAssertEqual(point.z, -0.2, accuracy: 0.0001)
    }

    func testPlaneRectangleScoreAcceptsPerspectiveProjectionOnceMappedToPlane() {
        let points = [
            SIMD2<Float>(-0.105, 0.1485),
            SIMD2<Float>(0.105, 0.1485),
            SIMD2<Float>(0.105, -0.1485),
            SIMD2<Float>(-0.105, -0.1485)
        ]

        XCTAssertGreaterThan(ScannerV2PlaneGeometry.rectangleScore(points), 0.95)
    }

    func testPlaneRectangleScoreRejectsArbitraryQuadrilateral() {
        let points = [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(0.22, 0.02),
            SIMD2<Float>(0.13, -0.25),
            SIMD2<Float>(-0.08, -0.10)
        ]

        XCTAssertLessThan(ScannerV2PlaneGeometry.rectangleScore(points), 0.70)
    }

    func testTemporalTrackerRequiresConsistentFramesBeforeReady() {
        var tracker = ScannerV2StabilityTracker(requiredSamples: 5, maximumCornerDrift: 0.012)
        let base = ScannerV2Quadrilateral(
            topLeft: CGPoint(x: 0.2, y: 0.8),
            topRight: CGPoint(x: 0.8, y: 0.8),
            bottomRight: CGPoint(x: 0.8, y: 0.2),
            bottomLeft: CGPoint(x: 0.2, y: 0.2)
        )

        for index in 0..<4 {
            XCTAssertFalse(tracker.append(base.offset(dx: CGFloat(index) * 0.001, dy: 0)))
        }
        XCTAssertTrue(tracker.append(base.offset(dx: 0.003, dy: 0.001)))
    }

    func testTemporalTrackerResetsAfterLargeJump() {
        var tracker = ScannerV2StabilityTracker(requiredSamples: 4, maximumCornerDrift: 0.01)
        let first = ScannerV2Quadrilateral(
            topLeft: CGPoint(x: 0.2, y: 0.8),
            topRight: CGPoint(x: 0.8, y: 0.8),
            bottomRight: CGPoint(x: 0.8, y: 0.2),
            bottomLeft: CGPoint(x: 0.2, y: 0.2)
        )
        _ = tracker.append(first)
        _ = tracker.append(first.offset(dx: 0.002, dy: 0))

        let jumped = first.offset(dx: 0.15, dy: 0)
        XCTAssertFalse(tracker.append(jumped))
        XCTAssertEqual(tracker.sampleCount, 1)
    }

    func testCaptureGateRequiresGeometryStabilityAndCameraReadiness() {
        let ready = ScannerV2CaptureGate.evaluate(
            hasDocument: true,
            documentStable: true,
            cameraStable: true,
            planeScore: 0.94,
            planeAvailable: true,
            focusAdjusting: false,
            exposureAdjusting: false,
            sharpnessScore: 0.8
        )
        XCTAssertEqual(ready, .ready)

        XCTAssertEqual(
            ScannerV2CaptureGate.evaluate(
                hasDocument: true,
                documentStable: true,
                cameraStable: true,
                planeScore: 0.45,
                planeAvailable: true,
                focusAdjusting: false,
                exposureAdjusting: false,
                sharpnessScore: 0.8
            ),
            .alignDocument
        )

        XCTAssertEqual(
            ScannerV2CaptureGate.evaluate(
                hasDocument: true,
                documentStable: true,
                cameraStable: false,
                planeScore: 0,
                planeAvailable: false,
                focusAdjusting: false,
                exposureAdjusting: false,
                sharpnessScore: 0.8
            ),
            .holdSteady
        )
    }
}

private extension ScannerV2Quadrilateral {
    func offset(dx: CGFloat, dy: CGFloat) -> ScannerV2Quadrilateral {
        ScannerV2Quadrilateral(
            topLeft: CGPoint(x: topLeft.x + dx, y: topLeft.y + dy),
            topRight: CGPoint(x: topRight.x + dx, y: topRight.y + dy),
            bottomRight: CGPoint(x: bottomRight.x + dx, y: bottomRight.y + dy),
            bottomLeft: CGPoint(x: bottomLeft.x + dx, y: bottomLeft.y + dy)
        )
    }
}
