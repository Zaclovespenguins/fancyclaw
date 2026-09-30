import SwiftUI
import Textual

/// Font-relative default blocks, hierarchical lists, and scrollable tables share our code chrome.
public struct FancyClawStructuredTextStyle: StructuredText.Style {
    public let inlineStyle = InlineStyle()
        .code(.monospaced, .fontScale(0.9))
        .strong(.fontWeight(.semibold))
        .link(.foregroundColor(.accentColor))
    public let headingStyle = StructuredText.DefaultStyle().headingStyle
    public let paragraphStyle = StructuredText.DefaultParagraphStyle()
    public let blockQuoteStyle = StructuredText.DefaultStyle().blockQuoteStyle
    public let codeBlockStyle = FancyClawCodeBlockStyle()
    public let listItemStyle = StructuredText.DefaultStyle().listItemStyle
    public let unorderedListMarker = StructuredText.HierarchicalSymbolListMarker(.disc, .circle, .square)
    public let orderedListMarker = StructuredText.DefaultStyle().orderedListMarker
    public let tableStyle = StructuredText.OverflowTableStyle()
    public let tableCellStyle = StructuredText.DefaultStyle().tableCellStyle
    public let thematicBreakStyle = StructuredText.DefaultStyle().thematicBreakStyle

    public init() {}
}
