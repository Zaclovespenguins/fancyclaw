import Testing
@testable import DesignSystem

struct MarkdownDetailsParserTests {
    private let example = "<details><summary>Collapsible Section</summary>Hidden content with **markdown**</details>"

    private func content(_ source: String) -> [MarkdownSegment.Content] {
        MarkdownDetailsParser.segments(in: source).map(\.content)
    }

    private func details(_ source: String) throws -> (summary: String, children: [MarkdownSegment], open: Bool) {
        let segment = try #require(MarkdownDetailsParser.segments(in: source).first)
        guard case .details(let summary, let children, let open) = segment.content else {
            Issue.record("Expected a details segment")
            throw TestError.notDetails
        }
        return (summary, children, open)
    }

    private enum TestError: Error { case notDetails }

    @Test func ordinaryMarkdownIsPreservedVerbatim() {
        let source = "## Heading\n\n- **bold**\n- [link](relative)\n\n```swift\nlet x = 1\n```\n"
        #expect(content(source) == [.markdown(source)])
        #expect(content(" \n\t ").isEmpty)
    }

    @Test func parsesTheRequestedSection() throws {
        let section = try details(example)
        #expect(section.summary == "Collapsible Section")
        #expect(section.children.map(\.content) == [.markdown("Hidden content with **markdown**")])
        #expect(!section.open)
    }

    @Test func preservesSurroundingMarkdownAndMultipleSections() {
        let source = "Before\n\n\(example)\n\nBetween\n\n\(example)\n\nAfter"
        let segments = MarkdownDetailsParser.segments(in: source)
        #expect(segments.count == 5)
        #expect(segments[0].content == .markdown("Before\n\n"))
        #expect(segments[2].content == .markdown("\n\nBetween\n\n"))
        #expect(segments[4].content == .markdown("\n\nAfter"))
        #expect(Set(segments.map(\.id)).count == segments.count)
    }

    @Test func matchesNestedSectionsInsteadOfTheFirstClosingTag() throws {
        let source = "<details><summary>Outer</summary>Before \(example) After</details>"
        let outer = try details(source)
        #expect(outer.summary == "Outer")
        #expect(outer.children.count == 3)
        #expect(outer.children[0].content == .markdown("Before "))
        guard case .details(let summary, let children, _) = outer.children[1].content else {
            Issue.record("Expected a nested section"); return
        }
        #expect(summary == "Collapsible Section")
        #expect(children.map(\.content) == [.markdown("Hidden content with **markdown**")])
        #expect(outer.children[2].content == .markdown(" After"))
    }

    @Test func supportsMultilineSummaryCaseAndQuotedAttributes() throws {
        let section = try details("<DETAILS title='open > ignored' OPEN=false>\n <SUMMARY class=label>\n **Résumé 🦀** \n</SUMMARY>\nBody\n</DETAILS>")
        #expect(section.summary == "**Résumé 🦀**")
        #expect(section.open)
        #expect(section.children.map(\.content) == [.markdown("\nBody\n")])
        #expect(try !details("<details title=' open '><summary>Title</summary>Body</details>").open)
    }

    @Test(arguments: ["```html", "~~~~html", "   ```html"])
    func fencedExamplesStayLiteral(fence: String) {
        let close = fence.contains("~") ? "~~~~" : "```"
        let source = "\(fence)\n\(example)\n\(close)\n\n\(example)"
        let segments = MarkdownDetailsParser.segments(in: source)
        #expect(segments.count == 2)
        #expect(segments[0].content == .markdown("\(fence)\n\(example)\n\(close)\n\n"))
        if case .details = segments[1].content {} else { Issue.record("Expected the section after the code fence") }
    }

    @Test func codeFenceWithinASectionDoesNotCloseIt() throws {
        let source = "<details><summary>Example</summary>\n```html\n</details>\n\(example)\n```\nTail\n</details>"
        let section = try details(source)
        #expect(section.children.map(\.content) == [.markdown("\n```html\n</details>\n\(example)\n```\nTail\n")])
    }

    @Test(arguments: ["`", "``", "````"])
    func inlineCodeExamplesStayLiteral(delimiter: String) {
        let source = "Example: \(delimiter)\(example)\(delimiter)."
        #expect(content(source) == [.markdown(source)])
    }

    @Test func escapesCommentsAndIndentedCodeStayLiteral() {
        for source in ["\\\(example)", "<!-- \(example) -->", "    \(example)", "\t\(example)"] {
            #expect(content(source) == [.markdown(source)])
        }
        #expect(content("<details-extra>Body</details-extra>") == [.markdown("<details-extra>Body</details-extra>")])
    }

    @Test func unmatchedBackticksDoNotHideARealSection() {
        let segments = MarkdownDetailsParser.segments(in: "A literal ` followed by \(example)")
        #expect(segments.count == 2)
        if case .details = segments[1].content {} else { Issue.record("Expected a section") }
    }

    @Test func incompleteStreamingTagsStayUnchanged() {
        // Every character prefix remains ordinary Markdown until the entire section is closed.
        for end in example.indices.dropFirst() {
            let prefix = String(example[..<end])
            #expect(content(prefix) == [.markdown(prefix)])
        }
        #expect(content("<details><summary>Outer</summary>\(example)") == [.markdown("<details><summary>Outer</summary>\(example)")])
    }

    @Test func missingAndEmptySummariesUseAnAccessibleDefault() throws {
        #expect(try details("<details>Body</details>").summary == "Details")
        #expect(try details("<details><summary> \n </summary>Body</details>").summary == "Details")
        #expect(try details("<details><summary>Title</summary></details>").children.isEmpty)
    }

    @Test(arguments: [
        "<details><summary>Missing summary close</details>",
        "<details title='unterminated><summary>Title</summary>Body</details>",
        "<details><summary>Wrong close</details></summary>",
        "<details/><summary>Not a section</summary>"
    ])
    func malformedTagsRemainOrdinaryMarkdown(source: String) {
        #expect(content(source) == [.markdown(source)])
    }

    @Test func deeplyNestedOutputHasABoundedViewTree() {
        let source = String(repeating: "<details><summary>Nested</summary>", count: 80)
            + "Body" + String(repeating: "</details>", count: 80)
        var segments = MarkdownDetailsParser.segments(in: source)
        var depth = 0
        while let first = segments.first, case .details(_, let children, _) = first.content {
            depth += 1
            segments = children
        }
        #expect(depth == 32)
        #expect(segments.count == 1)
        if case .markdown(let remainder) = segments.first?.content {
            #expect(remainder.contains("Body"))
            #expect(remainder.hasPrefix("<details>"))
        } else { Issue.record("Expected the remaining source to use Textual") }
    }

    @Test func identitiesSurviveReparsingAndGrowingContent() {
        let before = "Résumé 🦀\n\n"
        let short = MarkdownDetailsParser.segments(in: before + example)
        let long = MarkdownDetailsParser.segments(in: before + example.replacingOccurrences(of: "</details>", with: " more text</details>") + "\nTail")
        #expect(short.map(\.id) == Array(long.prefix(2)).map(\.id))
        #expect(short[1].id == before.utf8.count)
        #expect(short == MarkdownDetailsParser.segments(in: before + example))
    }
}
