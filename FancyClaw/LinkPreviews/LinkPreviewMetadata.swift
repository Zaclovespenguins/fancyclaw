import Foundation

/// Metadata and optional image bytes live in the memory cache only, never in SwiftData.
struct LinkPreviewMetadata: Sendable {
    let title: String
    let domain: String
    let imageData: Data?
    let iconData: Data?
    let isFallback: Bool

    static func fallback(for url: URL) -> Self {
        let domain = url.host() ?? url.absoluteString
        return .init(title: domain, domain: domain, imageData: nil, iconData: nil, isFallback: true)
    }

    var memoryCost: Int { (imageData?.count ?? 0) + (iconData?.count ?? 0) + title.utf8.count + domain.utf8.count }
}
