import CoreGraphics
import Foundation
import UIKit

/// Normalizes glasses photos (orientation, dead gray padding) before save and display.
enum CaptureImageProcessor {
    struct Prepared {
        let cgImage: CGImage
        let jpegData: Data
        let width: Int
        let height: Int
    }

    static func prepareForStorage(cgImage: CGImage, originalJPEG: Data?) -> Prepared? {
        if let originalJPEG,
           let oriented = CGImageJPEG.orientedUIImage(from: originalJPEG) {
            let normalized = oriented.normalizedUpOrientation()
            let trimmed = trimUniformPadding(from: normalized)
            return encode(trimmed)
        }

        let trimmed = trimUniformPadding(from: UIImage(cgImage: cgImage))
        return encode(trimmed)
    }

    static func imageForDisplay(fileURL: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        if let oriented = CGImageJPEG.orientedUIImage(from: data) {
            return trimUniformPadding(from: oriented.normalizedUpOrientation())
        }
        guard let ui = UIImage(contentsOfFile: fileURL.path) else { return nil }
        return trimUniformPadding(from: ui.normalizedUpOrientation())
    }

    private static func encode(_ image: UIImage) -> Prepared? {
        guard let cg = image.cgImage,
              let jpeg = image.jpegData(compressionQuality: 0.92) else { return nil }
        return Prepared(cgImage: cg, jpegData: jpeg, width: cg.width, height: cg.height)
    }

    /// Removes bottom/top bands the glasses ISP often leaves as flat gray in wide FOV buffers.
    static func trimUniformPadding(from image: UIImage, maxTrimFraction: CGFloat = 0.5) -> UIImage {
        guard let cg = image.cgImage,
              let rgba = rgbaBitmap(from: cg) else { return image }

        let width = rgba.width
        let height = rgba.height
        let bytes = rgba.bytes
        let maxTrimRows = Int(CGFloat(height) * maxTrimFraction)

        func rowIsPadding(_ y: Int) -> Bool {
            var sum = 0.0
            var sumSq = 0.0
            let row = y * width * 4
            for x in 0..<width {
                let i = row + x * 4
                let r = Double(bytes[i])
                let g = Double(bytes[i + 1])
                let b = Double(bytes[i + 2])
                let lum = 0.299 * r + 0.587 * g + 0.114 * b
                sum += lum
                sumSq += lum * lum
            }
            let n = Double(width)
            let mean = sum / n
            let variance = max(0, sumSq / n - mean * mean)
            let std = sqrt(variance)
            let isGray = mean > 35 && mean < 210
            let isFlat = std < 10
            return isGray && isFlat
        }

        var top = 0
        while top < maxTrimRows, rowIsPadding(top) {
            top += 1
        }

        var bottom = height
        var trimmedFromBottom = 0
        while trimmedFromBottom < maxTrimRows, bottom > top + 32 {
            if rowIsPadding(bottom - 1) {
                bottom -= 1
                trimmedFromBottom += 1
            } else {
                break
            }
        }

        guard bottom > top + 32, bottom - top < height else { return image }

        let cropH = bottom - top
        var cropBytes = [UInt8](repeating: 0, count: width * cropH * 4)
        for y in 0..<cropH {
            let src = ((top + y) * width * 4)..<((top + y + 1) * width * 4)
            let dst = (y * width * 4)..<((y + 1) * width * 4)
            cropBytes.replaceSubrange(dst, with: bytes[src])
        }

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: &cropBytes,
                  width: width,
                  height: cropH,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let cropped = ctx.makeImage() else {
            return image
        }

        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    private static func rgbaBitmap(from image: CGImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: &bytes,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (bytes, width, height)
    }
}

extension UIImage {
    func normalizedUpOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
