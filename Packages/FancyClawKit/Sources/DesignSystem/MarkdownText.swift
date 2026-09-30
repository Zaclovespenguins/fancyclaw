import SwiftUI
import Textual

/// Renders block-level Markdown for assistant messages.
///
/// A thin wrapper over Textual so feature code doesn't import it directly.
public struct MarkdownText: View {
    private let markdown: String

    public init(_ markdown: String) {
        self.markdown = markdown
    }

    public var body: some View {
        StructuredText(markdown: markdown)
            .textual.textSelection(.enabled)
    }
}

#Preview {
    MarkdownText("""
        # Hello
        Some **bold** text and `inline code`.

        - One
        - Two
        """)
        .padding()
}
