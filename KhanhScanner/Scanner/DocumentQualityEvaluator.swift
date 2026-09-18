import CoreGraphics
import Foundation

struct DocumentQuadrilateral: Equatable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    var points: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }
}

struct DocumentEdgeSupport: Equatable {
    let overall: CGFloat
    let weakestEnd: CGFloat
}

enum DocumentQuality: Equatable {
    case ready
    case flattenCorners
}

enum DocumentQualityEvaluator {
    private static let minimumConfidence: Float = 0.55
    private static let minimumArea: CGFloat = 0.12
    private static let minimumEdgeLength: CGFloat = 0.10
    private static let minimumCornerAngle = 30.0
    private static let maximumCornerAngle = 150.0
    private static let minimumOverallEdgeSupport: CGFloat = 0.62
    private static let minimumEdgeEndSupport: CGFloat = 0.32

    static func evaluate(
        _ quadrilateral: DocumentQuadrilateral,
        confidence: Float,
        edgeSupport: DocumentEdgeSupport? = nil
    ) -> DocumentQuality {
        guard confidence >= minimumConfidence,
              pointsAreNormalized(quadrilateral.points),
              polygonArea(quadrilateral.points) >= minimumArea,
              edges(of: quadrilateral.points).allSatisfy({ length($0.0, $0.1) >= minimumEdgeLength }),
              isConvex(quadrilateral.points),
              cornerAngles(of: quadrilateral.points).allSatisfy({
                  $0 >= minimumCornerAngle && $0 <= maximumCornerAngle
              }) else {
            return .flattenCorners
        }

        if let edgeSupport,
           edgeSupport.overall < minimumOverallEdgeSupport
            || edgeSupport.weakestEnd < minimumEdgeEndSupport {
            return .flattenCorners
        }

        return .ready
    }

    private static func pointsAreNormalized(_ points: [CGPoint]) -> Bool {
        points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) }
    }

    private static func edges(of points: [CGPoint]) -> [(CGPoint, CGPoint)] {
        points.indices.map { index in
            (points[index], points[(index + 1) % points.count])
        }
    }

    private static func length(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }

    private static func polygonArea(_ points: [CGPoint]) -> CGFloat {
        let twiceArea = points.indices.reduce(CGFloat.zero) { result, index in
            let next = points[(index + 1) % points.count]
            return result + points[index].x * next.y - next.x * points[index].y
        }
        return abs(twiceArea) / 2
    }

    private static func isConvex(_ points: [CGPoint]) -> Bool {
        let crossProducts = points.indices.map { index -> CGFloat in
            let first = points[index]
            let second = points[(index + 1) % points.count]
            let third = points[(index + 2) % points.count]
            return (second.x - first.x) * (third.y - second.y)
                - (second.y - first.y) * (third.x - second.x)
        }
        guard let first = crossProducts.first, abs(first) > .ulpOfOne else { return false }
        return crossProducts.allSatisfy { abs($0) > .ulpOfOne && ($0 > 0) == (first > 0) }
    }

    private static func cornerAngles(of points: [CGPoint]) -> [Double] {
        points.indices.map { index in
            let previous = points[(index - 1 + points.count) % points.count]
            let point = points[index]
            let next = points[(index + 1) % points.count]
            let first = CGVector(dx: previous.x - point.x, dy: previous.y - point.y)
            let second = CGVector(dx: next.x - point.x, dy: next.y - point.y)
            let denominator = hypot(first.dx, first.dy) * hypot(second.dx, second.dy)
            guard denominator > .ulpOfOne else { return 0 }
            let cosine = max(-1, min(1, (first.dx * second.dx + first.dy * second.dy) / denominator))
            return acos(Double(cosine)) * 180 / .pi
        }
    }
}

enum DocumentEdgeAnalyzer {
    private static let analysisSize = 256
    private static let samplesPerEdge = 48
    private static let endSampleCount = 12
    private static let normalSearchRadius = 4
    private static let minimumContrast = 32

    static func measure(
        in image: CGImage,
        quadrilateral: DocumentQuadrilateral
    ) -> DocumentEdgeSupport {
        guard let pixels = grayscalePixels(from: image) else {
            return DocumentEdgeSupport(overall: 0, weakestEnd: 0)
        }

        let points = quadrilateral.points.map { point in
            CGPoint(
                x: point.x * CGFloat(analysisSize - 1),
                y: point.y * CGFloat(analysisSize - 1)
            )
        }
        let edges = points.indices.map { index in
            (points[index], points[(index + 1) % points.count])
        }
        let supportByEdge = edges.map { edgeSupport(from: $0.0, to: $0.1, pixels: pixels) }
        let supportedCount = supportByEdge.flatMap { $0 }.filter { $0 }.count
        let totalCount = supportByEdge.count * samplesPerEdge
        let endScores = supportByEdge.flatMap { support in
            [
                fractionSupported(Array(support.prefix(endSampleCount))),
                fractionSupported(Array(support.suffix(endSampleCount)))
            ]
        }

        return DocumentEdgeSupport(
            overall: totalCount == 0 ? 0 : CGFloat(supportedCount) / CGFloat(totalCount),
            weakestEnd: endScores.min() ?? 0
        )
    }

    private static func grayscalePixels(from image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: analysisSize * analysisSize)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: analysisSize,
                height: analysisSize,
                bitsPerComponent: 8,
                bytesPerRow: analysisSize,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: analysisSize, height: analysisSize))
            return true
        }
        return rendered ? pixels : nil
    }

    private static func edgeSupport(from start: CGPoint, to end: CGPoint, pixels: [UInt8]) -> [Bool] {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let edgeLength = hypot(dx, dy)
        guard edgeLength > .ulpOfOne else {
            return [Bool](repeating: false, count: samplesPerEdge)
        }
        let normal = CGVector(dx: -dy / edgeLength, dy: dx / edgeLength)

        return (0..<samplesPerEdge).map { index in
            let amount = (CGFloat(index) + 0.5) / CGFloat(samplesPerEdge)
            let point = CGPoint(x: start.x + dx * amount, y: start.y + dy * amount)
            let values = (-normalSearchRadius...normalSearchRadius).compactMap { offset -> UInt8? in
                let x = Int(round(point.x + normal.dx * CGFloat(offset)))
                let y = Int(round(point.y + normal.dy * CGFloat(offset)))
                guard (0..<analysisSize).contains(x), (0..<analysisSize).contains(y) else { return nil }
                return pixels[y * analysisSize + x]
            }
            guard let darkest = values.min(), let brightest = values.max() else { return false }
            return Int(brightest) - Int(darkest) >= minimumContrast
        }
    }

    private static func fractionSupported(_ values: [Bool]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        return CGFloat(values.filter { $0 }.count) / CGFloat(values.count)
    }
}
