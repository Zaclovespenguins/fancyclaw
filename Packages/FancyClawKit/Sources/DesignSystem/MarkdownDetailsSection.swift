import SwiftUI
import Textual

struct MarkdownDetailsSection: View {
    let id: Int
    let summary: String
    let segments: [MarkdownSegment]
    let baseURL: URL?
    @State private var isExpanded: Bool

    init(id: Int, summary: String, segments: [MarkdownSegment], initiallyExpanded: Bool, baseURL: URL?) {
        self.id = id
        self.summary = summary
        self.segments = segments
        self.baseURL = baseURL
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            // Type erasure at this boundary bounds the recursive SwiftUI view type.
            AnyView(MarkdownSegmentsView(segments: segments, baseURL: baseURL))
        } label: {
            InlineText(markdown: summary, baseURL: baseURL, syntaxExtensions: [.math])
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .textual.textSelection(.disabled)
        }
        .accessibilityIdentifier("markdown.details.\(id)")
    }
}
