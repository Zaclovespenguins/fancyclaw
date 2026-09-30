import Foundation
import Textual
import UIKit

struct GatewayImageAttachmentLoader: AttachmentLoader {
    let load: @Sendable (URL) async throws -> Data

    func attachment(for url: URL, text: String, environment: ColorEnvironmentValues) async throws -> GatewayImageAttachment {
        let data = try await load(url)
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw URLError(.cannotDecodeContentData)
        }
        return GatewayImageAttachment(data: data, description: text, size: image.size)
    }
}
