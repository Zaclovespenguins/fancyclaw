import Foundation
import GatewayClient
import GatewayProtocol
import Testing
@testable import ChatCore

struct LinkPreviewExtractorTests {
    private func message(_ text: String, role: MessageRole = .assistant, streaming: Bool = false,
                         images: [ContentBlock.Media] = [], files: [ContentBlock.Media] = []) -> ConversationMessage {
        .init(id: "links", role: role, text: text, isStreaming: streaming, images: images, files: files)
    }

    @Test func finishedAssistantOnly() {
        let link = "https://example.com/report"
        #expect(LinkPreviewExtractor.urls(in: message(link)).count == 1)
        #expect(LinkPreviewExtractor.urls(in: message(link, role: .user)).isEmpty)
        #expect(LinkPreviewExtractor.urls(in: message(link, streaming: true)).isEmpty)
    }

    @MainActor @Test func systemAndToolHistoryCannotProducePreviewRows() {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()))
        store.reconcileHistory([
            .init(role: .system, content: [.text("https://system.example.com")], metadata: .init(id: "system")),
            .init(role: .toolResult, content: [.text("https://tool.example.com")], toolCallId: "tool", metadata: .init(id: "tool"))
        ])
        #expect(store.messages.flatMap { LinkPreviewExtractor.urls(in: $0) }.isEmpty)
    }

    @Test func encounterOrderDeduplicationAndThreeCardCap() {
        let links = LinkPreviewExtractor.urls(in: message("""
        [Report](https://example.com/report) https://example.com/report
        https://second.example.com/one https://third.example.com/two https://fourth.example.com/three
        """))
        #expect(links.map(\.host) == ["example.com", "second.example.com", "third.example.com"])
    }

    @Test func normalizesHostDefaultPortAndFragmentForDeduplication() {
        let links = LinkPreviewExtractor.urls(in: message("https://EXAMPLE.com:443/#intro https://example.com/ https://example.com/#other"))
        #expect(links.count == 1)
        #expect(links.first?.fragment == "intro")
    }

    @Test func gatewayOriginMapsWebSocketSchemeAndKeepsPortBoundary() throws {
        let gateway = try #require(URL(string: "wss://gateway.example.com/proxy/"))
        let links = LinkPreviewExtractor.urls(in: message("""
        https://gateway.example.com/settings https://gateway.example.com:443/status
        HTTPS://GATEWAY.EXAMPLE.COM/private
        https://gateway.example.com:8443/report http://gateway.example.com/public
        """), gatewayBaseURL: gateway)
        #expect(links.map(\.absoluteString) == ["https://gateway.example.com:8443/report", "http://gateway.example.com/public"])
    }

    @Test func excludesGatewayArtifactAndExplicitMediaReferences() throws {
        let gateway = try #require(URL(string: "ws://127.0.0.1:12345/proxy/"))
        let links = LinkPreviewExtractor.urls(in: message("""
        http://127.0.0.1:12345/help https://cdn.example.com/image.png#full
        https://cdn.example.com/report.pdf https://other.example.com/api/chat/media/outgoing/full
        https://other.example.com/api/artifacts/123 https://example.com/article
        """, images: [.init(kind: .image, url: "https://cdn.example.com/image.png")],
        files: [.init(kind: .file, url: "https://cdn.example.com/report.pdf")]), gatewayBaseURL: gateway)
        #expect(links.map(\.absoluteString) == ["https://example.com/article"])
    }

    @Test func rejectsNonWebAndCredentialBearingURLs() {
        #expect(LinkPreviewExtractor.urls(in: message("mailto:test@example.com ftp://example.com/file artifact://report https://user:secret@example.com/private https://example.com/public")).map(\.absoluteString)
                == ["https://example.com/public"])
    }

    @Test func codeExamplesAndMarkdownImagesAreNotPreviews() {
        let links = LinkPreviewExtractor.urls(in: message("""
        `https://inline.example.com` and ![A diagram](https://image.example.com/chart.png)
        ```swift
        let url = "https://code.example.com"
        ```
        ~~~text
        https://tilde.example.com
        ~~~
        See [the article](https://article.example.com/post).
        """))
        #expect(links.map(\.absoluteString) == ["https://article.example.com/post"])
    }

    @Test func unfinishedCodeFenceAndPunctuation() {
        #expect(LinkPreviewExtractor.urls(in: message("Read https://example.com/post.\n```\nhttps://unfinished.example.com")).map(\.absoluteString)
                == ["https://example.com/post"])
    }

    @Test func referenceAndShortcutImagesDoNotBecomeCards() {
        let links = LinkPreviewExtractor.urls(in: message("""
        ![Diagram][chart] ![Logo][] ![shortcut]
        [chart]: https://image.example.com/chart.png
        [logo]: https://image.example.com/logo.png
        [shortcut]: https://image.example.com/shortcut.png
        [documentation]: https://docs.example.com/article
        """))
        #expect(links.map(\.absoluteString) == ["https://docs.example.com/article"])
    }

    @Test func imageDefinitionsInsideCodeDoNotHideFollowingLinks() {
        #expect(LinkPreviewExtractor.urls(in: message("""
        ```markdown
        ![Image][chart]
        [chart]: https://image.example.com/chart.png
        ```
        Read https://example.com/article
        """)).map(\.absoluteString) == ["https://example.com/article"])
    }

    @Test func codeExampleImageReferencesDoNotClaimOutsideLinkDefinitions() {
        #expect(LinkPreviewExtractor.urls(in: message("""
        ```markdown
        ![Example image][article]
        ```
        `![Inline example][other]`
        [Read the article][article] and [another article][other].
        [article]: https://example.com/article
        [other]: https://second.example.com/article
        """)).map(\.absoluteString) == ["https://example.com/article", "https://second.example.com/article"])
    }
}
