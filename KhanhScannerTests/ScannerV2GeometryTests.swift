import CoreImage
import XCTest
import simd
import UIKit
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

    func testPlaneRectangleFitRegularizesNoisyDetectedCorners() throws {
        let ideal = [
            SIMD2<Float>(-0.105, 0.1485),
            SIMD2<Float>(0.105, 0.1485),
            SIMD2<Float>(0.105, -0.1485),
            SIMD2<Float>(-0.105, -0.1485)
        ]
        let noisy = [
            SIMD2<Float>(-0.113, 0.154),
            SIMD2<Float>(0.108, 0.141),
            SIMD2<Float>(0.112, -0.146),
            SIMD2<Float>(-0.099, -0.154)
        ]

        let fitted = try XCTUnwrap(ScannerV2PlaneGeometry.fittedRectangle(noisy))

        XCTAssertGreaterThan(ScannerV2PlaneGeometry.rectangleScore(fitted), 0.995)
        for (actual, expected) in zip(fitted, ideal) {
            XCTAssertLessThan(simd_distance(actual, expected), 0.018)
        }
    }

    func testWorldRectangleRegularizationUsesPlaneCoordinateSystem() throws {
        let angle: Float = .pi / 5
        let rotation = simd_float4x4(
            SIMD4<Float>(cos(angle), 0, -sin(angle), 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(sin(angle), 0, cos(angle), 0),
            SIMD4<Float>(0.4, 0.7, -1.2, 1)
        )

        let noisyLocal = [
            SIMD2<Float>(-0.113, 0.154),
            SIMD2<Float>(0.108, 0.141),
            SIMD2<Float>(0.112, -0.146),
            SIMD2<Float>(-0.099, -0.154)
        ]
        let world = noisyLocal.map { point -> SIMD3<Float> in
            let value = rotation * SIMD4<Float>(point.x, 0, point.y, 1)
            return SIMD3<Float>(value.x, value.y, value.z)
        }

        let fitted = try XCTUnwrap(
            ScannerV2PlaneGeometry.regularizedWorldRectangle(
                world,
                planeTransform: rotation
            )
        )

        XCTAssertEqual(fitted.count, 4)
        let local = fitted.map { point -> SIMD2<Float> in
            let value = simd_inverse(rotation) * SIMD4<Float>(point.x, point.y, point.z, 1)
            return SIMD2<Float>(value.x, value.z)
        }
        XCTAssertGreaterThan(ScannerV2PlaneGeometry.rectangleScore(local), 0.995)
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
    func testViewportMapperDoesNotRotatePortraitVisionCoordinatesTwice() {
        let viewport = CGSize(width: 832, height: 1797)
        let orientedImage = CGSize(width: 1440, height: 1920)

        let center = ScannerV2ViewportMapper.viewPoint(
            for: CGPoint(x: 0.5, y: 0.5),
            orientedImageSize: orientedImage,
            viewportSize: viewport
        )
        XCTAssertEqual(center.x, 416, accuracy: 0.5)
        XCTAssertEqual(center.y, 898.5, accuracy: 0.5)

        let upperLeftQuarter = ScannerV2ViewportMapper.viewPoint(
            for: CGPoint(x: 0.25, y: 0.75),
            orientedImageSize: orientedImage,
            viewportSize: viewport
        )
        XCTAssertEqual(upperLeftQuarter.x, 79.1, accuracy: 1.0)
        XCTAssertEqual(upperLeftQuarter.y, 449.25, accuracy: 1.0)
    }

    func testPlaneRectangleScoreWorksDirectlyIn3D() {
        let points = [
            SIMD3<Float>(-0.105, 0, 0.1485),
            SIMD3<Float>(0.105, 0, 0.1485),
            SIMD3<Float>(0.105, 0, -0.1485),
            SIMD3<Float>(-0.105, 0, -0.1485)
        ]

        XCTAssertGreaterThan(ScannerV2PlaneGeometry.rectangleScore3D(points), 0.95)
    }

    func testCameraMotionTrackerNeedsSeveralQuietFrames() {
        var tracker = ScannerV2CameraMotionTracker(requiredSamples: 4)
        let base = matrix_identity_float4x4

        XCTAssertFalse(tracker.append(base))
        XCTAssertFalse(tracker.append(base))
        XCTAssertFalse(tracker.append(base))
        XCTAssertTrue(tracker.append(base))
    }

    func testCameraMotionTrackerResetsAfterLargeMovement() {
        var tracker = ScannerV2CameraMotionTracker(requiredSamples: 3)
        let base = matrix_identity_float4x4
        _ = tracker.append(base)
        _ = tracker.append(base)

        var moved = base
        moved.columns.3.x = 0.08

        XCTAssertFalse(tracker.append(moved))
        XCTAssertEqual(tracker.sampleCount, 1)
    }

    func testCameraMotionTrackerDetectsRollRotation() {
        var tracker = ScannerV2CameraMotionTracker(requiredSamples: 3, maximumRotationDelta: 0.035)
        let base = matrix_identity_float4x4
        _ = tracker.append(base)
        _ = tracker.append(base)

        let angle: Float = 0.12
        var rotated = matrix_identity_float4x4
        rotated.columns.0 = SIMD4<Float>(cos(angle), sin(angle), 0, 0)
        rotated.columns.1 = SIMD4<Float>(-sin(angle), cos(angle), 0, 0)

        XCTAssertFalse(tracker.append(rotated))
        XCTAssertEqual(tracker.sampleCount, 1)
    }

    func testCapturedReadinessGivesExplicitMoveToNextPageInstruction() {
        XCTAssertEqual(
            ScannerV2CaptureReadiness.captured.statusText,
            "Captured — move to next page"
        )
    }

    func testAutoCaptureDoesNotRearmAfterBriefDetectionFlicker() {
        var gate = ScannerV2AutoCaptureRearmGate(requiredMissingFrames: 8)
        gate.markCaptured()

        for _ in 0..<3 {
            gate.observeDocument(present: false)
        }
        gate.observeDocument(present: true)

        XCTAssertFalse(gate.isArmed)
    }

    func testAutoCaptureRearmsAfterDocumentActuallyLeavesFrame() {
        var gate = ScannerV2AutoCaptureRearmGate(requiredMissingFrames: 8)
        gate.markCaptured()

        for _ in 0..<7 {
            gate.observeDocument(present: false)
            XCTAssertFalse(gate.isArmed)
        }

        gate.observeDocument(present: false)
        XCTAssertTrue(gate.isArmed)
    }

    func testPageChangeDetectorBlocksDuplicateUntilDocumentMoves() {
        var detector = ScannerV2PageChangeDetector(minimumChange: 0.05)
        let page = ScannerV2Quadrilateral(
            topLeft: CGPoint(x: 0.2, y: 0.8),
            topRight: CGPoint(x: 0.8, y: 0.8),
            bottomRight: CGPoint(x: 0.8, y: 0.2),
            bottomLeft: CGPoint(x: 0.2, y: 0.2)
        )

        detector.markCaptured(page)
        XCTAssertFalse(detector.canCapture(page.offset(dx: 0.005, dy: 0)))
        XCTAssertTrue(detector.canCapture(page.offset(dx: 0.12, dy: 0)))
    }

    func testSharpnessEstimatorDistinguishesEdgesFromFlatImage() {
        let flat = testImage(checkerboard: false)
        let sharp = testImage(checkerboard: true)

        XCTAssertGreaterThan(
            ScannerV2ImageProcessor.sharpnessScore(of: sharp),
            ScannerV2ImageProcessor.sharpnessScore(of: flat) + 0.2
        )
    }

    func testSharpnessEstimatorTreatsSparseDocumentTextAsSharp() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let page = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            UIColor.black.setFill()
            for row in 0..<4 {
                context.fill(CGRect(x: 18, y: 28 + row * 20, width: 92, height: 2))
            }
        }

        XCTAssertGreaterThan(ScannerV2ImageProcessor.sharpnessScore(of: page), 0.25)
    }

    func testPageChangeDetectorAllowsNewContentAtSameGeometry() throws {
        var detector = ScannerV2PageChangeDetector(
            minimumChange: 0.05,
            minimumContentChange: 0.12
        )
        let geometry = ScannerV2Quadrilateral(
            topLeft: CGPoint(x: 0.2, y: 0.8),
            topRight: CGPoint(x: 0.8, y: 0.8),
            bottomRight: CGPoint(x: 0.8, y: 0.2),
            bottomLeft: CGPoint(x: 0.2, y: 0.2)
        )

        let first = try XCTUnwrap(
            ScannerV2ImageProcessor.pageFingerprint(of: fingerprintPage(variant: 0))
        )
        let same = try XCTUnwrap(
            ScannerV2ImageProcessor.pageFingerprint(of: fingerprintPage(variant: 0))
        )
        let changed = try XCTUnwrap(
            ScannerV2ImageProcessor.pageFingerprint(of: fingerprintPage(variant: 1))
        )

        detector.markCaptured(geometry, fingerprint: first)

        XCTAssertFalse(detector.canCapture(geometry, fingerprint: same))
        XCTAssertTrue(detector.canCapture(geometry, fingerprint: changed))
    }

    func testSharpnessEstimatorDropsForBlurredEdges() throws {
        let sharp = testImage(checkerboard: true)
        let input = try XCTUnwrap(CIImage(image: sharp))
        let filter = try XCTUnwrap(CIFilter(name: "CIGaussianBlur"))
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(3.0, forKey: kCIInputRadiusKey)
        let output = try XCTUnwrap(filter.outputImage?.cropped(to: input.extent))
        let context = CIContext()
        let cgImage = try XCTUnwrap(context.createCGImage(output, from: output.extent))
        let blurred = UIImage(cgImage: cgImage)

        XCTAssertGreaterThan(
            ScannerV2ImageProcessor.sharpnessScore(of: sharp),
            ScannerV2ImageProcessor.sharpnessScore(of: blurred) + 0.08
        )
    }


    func testPerspectiveCorrectionRunsBorderCleanupBeforeReturningPage() throws {
        let source = pageWithBackgroundSlivers()
        let quadrilateral = ScannerV2Quadrilateral(
            topLeft: CGPoint(x: 0, y: 1),
            topRight: CGPoint(x: 1, y: 1),
            bottomRight: CGPoint(x: 1, y: 0),
            bottomLeft: CGPoint(x: 0, y: 0)
        )
        let corrected = try XCTUnwrap(
            ScannerV2ImageProcessor.correctedImage(
                from: try XCTUnwrap(CIImage(image: source)),
                quadrilateral: quadrilateral
            )
        )

        XCTAssertLessThan(corrected.size.width, source.size.width)
        XCTAssertLessThan(corrected.size.height, source.size.height)
    }

    func testBorderCleanupRemovesThinBackgroundSlivers() throws {
        let source = pageWithBackgroundSlivers()
        let cleaned = try XCTUnwrap(
            ScannerV2ImageProcessor.trimBackgroundSlivers(from: source)
        )

        XCTAssertLessThan(cleaned.size.width, source.size.width)
        XCTAssertLessThan(cleaned.size.height, source.size.height)

        let corner = try pixel(cleaned, x: 1, y: 1)
        XCTAssertGreaterThan(luminance(corner), 0.80)
    }

    func testBorderCleanupDoesNotCropAlreadyCleanPage() throws {
        let source = cleanDocumentPage()
        let cleaned = try XCTUnwrap(
            ScannerV2ImageProcessor.trimBackgroundSlivers(from: source)
        )

        XCTAssertEqual(cleaned.size.width, source.size.width, accuracy: 0.5)
        XCTAssertEqual(cleaned.size.height, source.size.height, accuracy: 0.5)
    }

    func testDocumentSignalsIgnoreSharpBackgroundOutsidePage() throws {
        let first = documentScene(backgroundPattern: 0)
        let second = documentScene(backgroundPattern: 1)
        let quadrilateral = ScannerV2Quadrilateral(
            topLeft: CGPoint(x: 0.25, y: 0.75),
            topRight: CGPoint(x: 0.75, y: 0.75),
            bottomRight: CGPoint(x: 0.75, y: 0.25),
            bottomLeft: CGPoint(x: 0.25, y: 0.25)
        )

        let firstSignals = try XCTUnwrap(
            ScannerV2ImageProcessor.documentSignals(
                from: try XCTUnwrap(CIImage(image: first)),
                quadrilateral: quadrilateral
            )
        )
        let secondSignals = try XCTUnwrap(
            ScannerV2ImageProcessor.documentSignals(
                from: try XCTUnwrap(CIImage(image: second)),
                quadrilateral: quadrilateral
            )
        )

        XCTAssertEqual(firstSignals.fingerprint, secondSignals.fingerprint)
        XCTAssertEqual(firstSignals.sharpness, secondSignals.sharpness, accuracy: 0.02)
    }

    private func fingerprintPage(variant: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            UIColor.black.setFill()

            if variant == 0 {
                for row in 0..<5 {
                    context.fill(CGRect(x: 18, y: 24 + row * 17, width: 92, height: 3))
                }
            } else {
                for column in 0..<4 {
                    context.fill(CGRect(x: 24 + column * 23, y: 18, width: 3, height: 92))
                }
            }
        }
    }


    private func cleanDocumentPage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: 160, height: 220),
            format: format
        ).image { context in
            UIColor(red: 0.93, green: 0.92, blue: 0.89, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 220))
            UIColor.black.setFill()
            for row in 0..<6 {
                context.fill(CGRect(x: 24, y: 36 + row * 22, width: 112, height: 3))
            }
        }
    }

    private func pageWithBackgroundSlivers() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: 160, height: 220),
            format: format
        ).image { context in
            UIColor(white: 0.18, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 220))

            UIColor(red: 0.93, green: 0.92, blue: 0.89, alpha: 1).setFill()
            context.fill(CGRect(x: 8, y: 0, width: 152, height: 213))

            UIColor.black.setFill()
            for row in 0..<6 {
                context.fill(CGRect(x: 28, y: 36 + row * 22, width: 108, height: 3))
            }
        }
    }

    private func pixel(
        _ image: UIImage,
        x: Int,
        y: Int
    ) throws -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            )
        )
        context.interpolationQuality = .none
        context.draw(
            cg,
            in: CGRect(
                x: -x,
                y: y - Int(image.size.height) + 1,
                width: Int(image.size.width),
                height: Int(image.size.height)
            )
        )
        return (
            CGFloat(bytes[0]) / 255,
            CGFloat(bytes[1]) / 255,
            CGFloat(bytes[2]) / 255
        )
    }

    private func luminance(
        _ c: (r: CGFloat, g: CGFloat, b: CGFloat)
    ) -> CGFloat {
        0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    private func documentScene(backgroundPattern: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { context in
            if backgroundPattern == 0 {
                UIColor.darkGray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            } else {
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
                UIColor.white.setFill()
                for index in stride(from: 0, to: 200, by: 10) {
                    context.fill(CGRect(x: index, y: 0, width: 4, height: 200))
                }
            }

            UIColor.white.setFill()
            context.fill(CGRect(x: 50, y: 50, width: 100, height: 100))
            UIColor.black.setFill()
            for row in 0..<4 {
                context.fill(CGRect(x: 68, y: 72 + row * 18, width: 64, height: 3))
            }
        }
    }

    private func testImage(checkerboard: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            guard checkerboard else { return }

            UIColor.black.setFill()
            for y in stride(from: 0, to: 64, by: 8) {
                for x in stride(from: 0, to: 64, by: 8) where ((x + y) / 8).isMultiple(of: 2) {
                    context.fill(CGRect(x: x, y: y, width: 8, height: 8))
                }
            }
        }
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
