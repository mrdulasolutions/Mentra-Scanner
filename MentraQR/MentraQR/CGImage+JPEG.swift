import CoreGraphics
import Foundation
import ImageIO
import UIKit

enum CGImageJPEG {
    private static let fullDecodeOptions: [CFString: Any] = [
        kCGImageSourceShouldCache: false,
        kCGImageSourceCreateThumbnailFromImageAlways: false,
        kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
    ]

    static func make(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, fullDecodeOptions as CFDictionary)
    }

    static func orientedUIImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, fullDecodeOptions as CFDictionary)
        else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exifOrientation = (props?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let orientation = uiImageOrientation(fromExifOrientation: exifOrientation)
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    /// Maps TIFF/EXIF `kCGImagePropertyOrientation` (1…8) to `UIImage.Orientation` (not the same as rawValue).
    private static func uiImageOrientation(fromExifOrientation exif: Int) -> UIImage.Orientation {
        switch exif {
        case 2: return .upMirrored
        case 3: return .down
        case 4: return .downMirrored
        case 5: return .leftMirrored
        case 6: return .right
        case 7: return .rightMirrored
        case 8: return .left
        default: return .up
        }
    }

    static func pixelSize(from data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
}
