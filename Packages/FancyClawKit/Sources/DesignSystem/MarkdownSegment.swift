/// Source byte offsets keep section identity stable as a streamed message grows.
struct MarkdownSegment: Identifiable, Equatable, Sendable {
    let id: Int
    let content: Content

    enum Content: Equatable, Sendable {
        case markdown(String)
        case details(summary: String, segments: [MarkdownSegment], initiallyExpanded: Bool)
    }
}
