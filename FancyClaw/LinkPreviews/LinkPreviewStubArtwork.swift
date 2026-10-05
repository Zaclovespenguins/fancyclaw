import DesignSystem
import SwiftUI

/// Deterministic local raster fixtures exercise the image and favicon surfaces without any network request.
enum LinkPreviewStubArtwork {
    static let image = artwork(size: CGSize(width: 400, height: 260))
    static let icon = artwork(size: CGSize(width: 40, height: 40))

    private static func artwork(size: CGSize) -> Data {
        let theme = AppTheme.coral
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor(theme.avatarStart.color).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(theme.avatarEnd.color).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: -size.width * 0.3, y: size.height * 0.4,
                                                    width: size.width * 1.4, height: size.height * 1.4))
            let side = min(size.width, size.height) * 0.52
            UIImage(systemName: "swift")?
                .withTintColor(UIColor(theme.textOnAvatar), renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side))
        }
    }
}
