import CoreGraphics
import Foundation

enum VisionFrameScaler {
    /// Upscale small stream frames so Code128/PDF417 decode more reliably on glasses video.
    static func scaledForBarcodeScan(_ image: CGImage, minLongEdge: CGFloat = 1600) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let longEdge = max(width, height)
        guard longEdge < minLongEdge, longEdge > 0 else { return image }

        let scale = minLongEdge / longEdge
        let newWidth = Int((width * scale).rounded(.up))
        let newHeight = Int((height * scale).rounded(.up))
        guard newWidth > 0, newHeight > 0 else { return image }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }
}
