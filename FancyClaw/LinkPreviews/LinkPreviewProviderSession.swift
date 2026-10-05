import Foundation
import DesignSystem
@preconcurrency import LinkPresentation
import UniformTypeIdentifiers

/// Each visible card owns its provider. An eight-second overall deadline also bounds icon/image loading.
@MainActor final class LinkPreviewProviderSession {
    private let provider = LPMetadataProvider()
    private var imageRequests: [LinkPreviewImageRequest] = []

    init() { provider.timeout = 8 }

    func fetch(_ url: URL) async throws -> LinkPreviewMetadata {
        let metadata = try await provider.startFetchingMetadata(for: url)
        try Task.checkCancellation()
        let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = try await imageData(from: metadata.iconProvider, maxPixelSize: 128)
        let image = try await imageData(from: metadata.imageProvider, maxPixelSize: 1_024)
        try Task.checkCancellation()
        return .init(title: title.flatMap { $0.isEmpty ? nil : $0 } ?? url.host() ?? "Website",
                     domain: url.host() ?? "Website", imageData: image, iconData: icon, isFallback: false)
    }

    func cancel() {
        provider.cancel()
        imageRequests.forEach { $0.cancel() }
        imageRequests.removeAll()
    }

    private func imageData(from provider: NSItemProvider?, maxPixelSize: Int) async throws -> Data? {
        guard let provider,
              let identifier = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { return nil }
        let request = LinkPreviewImageRequest()
        imageRequests.append(request)
        let bytes = await request.load(provider, identifier: identifier)
        try Task.checkCancellation()
        let thumbnail = bytes.flatMap { PreviewImageDecoder.thumbnailPNG(from: $0, maxPixelSize: maxPixelSize) }
        try Task.checkCancellation()
        return thumbnail
    }
}
