import SwiftUI
import Textual

public struct UserMarkdownText: View {
    private let markdown: String
    public init(_ markdown: String) { self.markdown = markdown }
    public var body: some View {
        InlineText(markdown: markdown).textual.textSelection(.enabled)
    }
}
