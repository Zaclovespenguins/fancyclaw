import ImageIO
import Testing
import UIKit
@testable import DesignSystem

@MainActor struct PreviewImageDecoderTests {
    @Test func compressedLargeRasterIsDownsampledBeforeDisplay() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 2_048, height: 512), format: format).pngData { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2_048, height: 512))
        }
        let thumbnail = try #require(PreviewImageDecoder.thumbnailPNG(from: bytes, maxPixelSize: 128))
        let source = try #require(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 128)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 32)
    }

    @Test func malformedAndOversizedDataFallsBack() {
        #expect(PreviewImageDecoder.thumbnailPNG(from: Data([0, 1, 2]), maxPixelSize: 128) == nil)
        #expect(PreviewImageDecoder.thumbnailPNG(from: Data(repeating: 0, count: 5 * 1_024 * 1_024 + 1), maxPixelSize: 128) == nil)
    }
}
