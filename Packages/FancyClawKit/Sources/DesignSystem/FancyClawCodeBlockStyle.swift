import SwiftUI
import Textual

public struct FancyClawCodeBlockStyle: StructuredText.CodeBlockStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        MarkdownCodeBlock(configuration: configuration)
            .textual.blockSpacing(.fontScaled(top: 0.9, bottom: 0.4))
    }
}
