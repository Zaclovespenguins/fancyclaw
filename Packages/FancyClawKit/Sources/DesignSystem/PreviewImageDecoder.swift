import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downsamples before decoding, bounding raster memory as well as compressed input size.
public enum PreviewImageDecoder {
    public static func thumbnailPNG(from bytes: Data, maxPixelSize: Int) -> Data? {
        guard bytes.count <= 5 * 1_024 * 1_024, maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize, 1_024),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
