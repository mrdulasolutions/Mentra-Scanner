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
        let orientationRaw = (props?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let orientation = UIImage.Orientation(rawValue: orientationRaw) ?? .up
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
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
