import CoreGraphics
import Foundation

/// Normalized label region (Vision space: origin bottom-left, unit square).
enum LabelScanROI {
    /// Default “place shipping label here” guide for glasses POV.
    static let defaultGuide = CGRect(x: 0.10, y: 0.20, width: 0.80, height: 0.58)

    static func inferred(from barcodeBoxes: [CGRect], fallback: CGRect = defaultGuide) -> CGRect {
        guard !barcodeBoxes.isEmpty else { return fallback }
        var union = barcodeBoxes[0]
        for box in barcodeBoxes.dropFirst() {
            union = union.union(box)
        }
        let padX = max(0.04, union.width * 0.15)
        let padY = max(0.05, union.height * 0.35)
        var expanded = union.insetBy(dx: -padX, dy: -padY)
        expanded = expanded.intersection(unitSquare)
        if expanded.width < 0.2 || expanded.height < 0.15 {
            return fallback
        }
        return expanded
    }

    static func crop(_ image: CGImage, normalized: CGRect) -> CGImage? {
        let rect = pixelRect(normalized: normalized, imageWidth: image.width, imageHeight: image.height)
        guard rect.width >= 8, rect.height >= 8 else { return nil }
        return image.cropping(to: rect)
    }

    static func intersects(_ a: CGRect, _ b: CGRect, minimumOverlap: CGFloat = 0.2) -> Bool {
        let intersection = a.intersection(b)
        if intersection.isNull || intersection.isEmpty { return false }
        let areaA = a.width * a.height
        guard areaA > 0 else { return false }
        return (intersection.width * intersection.height) / areaA >= minimumOverlap
    }

    private static let unitSquare = CGRect(x: 0, y: 0, width: 1, height: 1)

    private static func pixelRect(normalized: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect {
        let w = CGFloat(imageWidth)
        let h = CGFloat(imageHeight)
        let x = normalized.minX * w
        let width = normalized.width * w
        let yTop = (1 - normalized.maxY) * h
        let height = normalized.height * h
        return CGRect(x: x, y: yTop, width: width, height: height).integral
    }
}
