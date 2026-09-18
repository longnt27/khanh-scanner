import XCTest
import UIKit
import simd
@testable import KhanhScanner

final class ScannerV2QualityTests: XCTestCase {
    func testSharpnessScoreSeparatesFlatFromHighFrequencyImage() throws {
        let flat = try XCTUnwrap(image { context, size in
            UIColor(white: 0.5, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.cgImage)

        let checkerboard = try XCTUnwrap(image { context, size in
            let cell: CGFloat = 4
            for row in 0..<Int(size.height / cell) {
                for column in 0..<Int(size.width / cell) {
                    ((row + column).isMultiple(of: 2) ? UIColor.black : UIColor.white).setFill()
                    context.fill(CGRect(
                        x: CGFloat(column) * cell,
                        y: CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    ))
                }
            }
        }.cgImage)

        let flatScore = ScannerV2Sharpness.score(flat)
        let detailedScore = ScannerV2Sharpness.score(checkerboard)

        XCTAssertLessThan(flatScore, 0.05)
        XCTAssertGreaterThan(detailedScore, flatScore + 0.25)
    }

    func testMotionTrackerRequiresSeveralStableCameraPoses() {
        var tracker = ScannerV2MotionTracker(
            requiredSamples: 4,
            maximumTranslationMeters: 0.006,
            maximumRotationRadians: 0.02
        )

        XCTAssertFalse(tracker.append(transform(x: 0, yaw: 0)))
        XCTAssertFalse(tracker.append(transform(x: 0.001, yaw: 0.003)))
        XCTAssertFalse(tracker.append(transform(x: 0.002, yaw: 0.005)))
        XCTAssertTrue(tracker.append(transform(x: 0.0025, yaw: 0.006)))
    }

    func testMotionTrackerResetsAfterCameraJump() {
        var tracker = ScannerV2MotionTracker(
            requiredSamples: 4,
            maximumTranslationMeters: 0.006,
            maximumRotationRadians: 0.02
        )

        _ = tracker.append(transform(x: 0, yaw: 0))
        _ = tracker.append(transform(x: 0.001, yaw: 0.004))
        _ = tracker.append(transform(x: 0.002, yaw: 0.006))

        XCTAssertFalse(tracker.append(transform(x: 0.04, yaw: 0.15)))
        XCTAssertEqual(tracker.sampleCount, 1)
    }

    private func image(
        size: CGSize = CGSize(width: 64, height: 64),
        draw: (CGContext, CGSize) -> Void
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            draw(renderer.cgContext, size)
        }
    }

    private func transform(x: Float, yaw: Float) -> simd_float4x4 {
        var rotation = matrix_identity_float4x4
        rotation.columns.0 = SIMD4<Float>(cos(yaw), 0, -sin(yaw), 0)
        rotation.columns.2 = SIMD4<Float>(sin(yaw), 0, cos(yaw), 0)
        rotation.columns.3 = SIMD4<Float>(x, 0, 0, 1)
        return rotation
    }
}
