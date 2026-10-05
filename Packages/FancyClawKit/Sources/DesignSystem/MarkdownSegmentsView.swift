import SwiftUI
import Textual

struct MarkdownSegmentsView: View {
    let segments: [MarkdownSegment]
    let baseURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ForEach(segments) { segment in
                switch segment.content {
                case .markdown(let source):
                    StructuredText(markdown: source, baseURL: baseURL, syntaxExtensions: [.math])
                case .details(let summary, let children, let initiallyExpanded):
                    MarkdownDetailsSection(id: segment.id, summary: summary, segments: children,
                        initiallyExpanded: initiallyExpanded, baseURL: baseURL)
                }
            }
        }
    }
}
