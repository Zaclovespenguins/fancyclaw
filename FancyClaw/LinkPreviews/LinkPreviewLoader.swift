import ChatCore
import SwiftUI

/// App-owned native metadata backend with a testable, bounded, completed-only memory cache.
@MainActor final class LinkPreviewLoader {
    private let cache = LinkPreviewCache<LinkPreviewMetadata>()
    private let isStubbed: Bool

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        // Future Demo modes are covered automatically. FakeGateway never contacts third-party sites.
        isStubbed = arguments.contains("-FakeGateway") || arguments.contains("-OnboardingPreview")
            || arguments.contains(where: { $0.hasPrefix("-Demo") })
        #else
        isStubbed = false
        #endif
    }

    func load(_ url: URL) async throws -> LinkPreviewMetadata {
        if isStubbed {
            return try await cache.load(url, fallback: .fallback(for: url), cost: { $0.memoryCost }, fetch: {
                try await Task.sleep(for: .milliseconds(80))
                if url.host() == "offline.example.com" { throw URLError(.notConnectedToInternet) }
                return .init(title: url.host() == "developer.apple.com" ? "Build thoughtful apps with SwiftUI" : "OpenClaw documentation",
                             domain: url.host() ?? "Website", imageData: LinkPreviewStubArtwork.image,
                             iconData: LinkPreviewStubArtwork.icon, isFallback: false)
            })
        }
        let session = LinkPreviewProviderSession()
        return try await cache.load(url, fallback: .fallback(for: url), cost: { $0.memoryCost },
                                    fetch: { try await session.fetch(url) }, cancel: { session.cancel() })
    }
}

private struct LinkPreviewLoaderKey: EnvironmentKey {
    static let defaultValue: LinkPreviewLoader? = nil
}

extension EnvironmentValues {
    var linkPreviewLoader: LinkPreviewLoader? {
        get { self[LinkPreviewLoaderKey.self] }
        set { self[LinkPreviewLoaderKey.self] = newValue }
    }
}
