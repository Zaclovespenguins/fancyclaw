import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum AttachmentDemo {
    public static func imageData() throws -> Data {
        guard let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 640 * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.75, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        context.setFillColor(CGColor(red: 0.9, green: 0.8, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 150))
        context.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.5, alpha: 1))
        context.fillEllipse(in: CGRect(x: 460, y: 320, width: 100, height: 100))
        let data = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileReadCorruptFile) }
        return data as Data
    }
}
