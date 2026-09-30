import SwiftUI
import Textual

/// Feature views don't import Textual. Links use SwiftUI's openURL environment action.
public struct MarkdownText: View {
    private let markdown: String
    private let baseURL: URL?
    private let imageLoader: @Sendable (URL) async throws -> Data

    public init(_ markdown: String, baseURL: URL? = nil,
                imageLoader: @escaping @Sendable (URL) async throws -> Data = { _ in throw URLError(.resourceUnavailable) }) {
        self.markdown = markdown
        self.baseURL = baseURL
        self.imageLoader = imageLoader
    }

    public var body: some View {
        StructuredText(markdown: markdown, baseURL: baseURL, syntaxExtensions: [.math])
            .textual.structuredTextStyle(FancyClawStructuredTextStyle())
            .textual.highlighterTheme(.default)
            .textual.imageAttachmentLoader(GatewayImageAttachmentLoader(load: imageLoader))
            .textual.textSelection(.enabled)
    }
}
