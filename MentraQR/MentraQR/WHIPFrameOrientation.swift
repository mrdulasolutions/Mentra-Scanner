import CoreGraphics
import UIKit

/// WHIP delivers BGRA as a `CGImage` whose storage order does not match UIKit top-left pixels.
/// One rasterization path for live preview, Vision, and JPEG so nothing disagrees.
enum WHIPFrameOrientation {
    /// Bakes the frame into UIKit-style upright pixels (same result for preview and file export).
    static func normalizedUIImage(from raw: CGImage) -> UIImage {
        let source = UIImage(cgImage: raw)
        let size = CGSize(width: raw.width, height: raw.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            source.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func normalizedCGImage(from raw: CGImage) -> CGImage? {
        normalizedUIImage(from: raw).cgImage
    }
}
