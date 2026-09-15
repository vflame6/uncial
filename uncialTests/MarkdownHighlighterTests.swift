import Foundation
import Testing
@testable import Uncial

@Suite struct MarkdownHighlighterTests {
    private func kinds(_ text: String) -> [(MarkdownHighlighter.Kind, String)] {
        MarkdownHighlighter.spans(in: text).map { ($0.kind, (text as NSString).substring(with: $0.range)) }
    }

    private func has(_ text: String, _ kind: MarkdownHighlighter.Kind, _ fragment: String) -> Bool {
        kinds(text).contains { $0.0 == kind && $0.1 == fragment }
    }

    @Test func headingsCoverTheWholeLine() {
        let text = "# Title\ntext"
        #expect(has(text, .heading, "# Title"))
        #expect(MarkdownHighlighter.spans(in: text).count == 1)
    }

    @Test func fencedCodeTracksState() {
        let text = "```swift\nlet x = *1*\n```\nafter *em*"
        let spans = kinds(text)
        #expect(spans.filter { $0.0 == .codeBlock }.map(\.1) == ["```swift", "let x = *1*", "```"])
        #expect(has(text, .emphasis, "*em*"))
        #expect(!has(text, .emphasis, "*1*"))
    }

    @Test func tildeFencesAndLongerClosersWork() {
        let text = "~~~\n```\nstill code\n~~~~\ndone"
        #expect(kinds(text).filter { $0.0 == .codeBlock }.count == 4)
        #expect(!has(text, .codeBlock, "done"))
    }

    @Test func inlineCodeMasksEmphasis() {
        let text = "`a*b*c` *d*"
        #expect(has(text, .inlineCode, "`a*b*c`"))
        #expect(has(text, .emphasis, "*d*"))
        #expect(!has(text, .emphasis, "*b*"))
    }

    @Test func strongAndEmphasis() {
        let text = "**bold** and _it_ and *em*"
        #expect(has(text, .strong, "**bold**"))
        #expect(has(text, .emphasis, "_it_"))
        #expect(has(text, .emphasis, "*em*"))
        #expect(!has(text, .emphasis, "*bold*"))
    }

    @Test func linksAndImages() {
        #expect(has("[text](http://x)", .link, "[text]"))
        #expect(has("[text](http://x)", .url, "(http://x)"))
        #expect(has("![alt](img.png)", .link, "![alt]"))
        #expect(has("![alt](img.png)", .url, "(img.png)"))
        #expect(has("see <https://a.b> now", .url, "<https://a.b>"))
    }

    @Test func listMarkersIncludingTasks() {
        #expect(has("- [ ] task", .listMarker, "- [ ] "))
        #expect(has("- [x] done", .listMarker, "- [x] "))
        #expect(has("1. item", .listMarker, "1. "))
        #expect(has("  * nested *em*", .listMarker, "  * "))
        #expect(has("  * nested *em*", .emphasis, "*em*"))
    }

    @Test func quotesAndRules() {
        #expect(has("> quote", .quote, "> quote"))
        let text = "a\n\n---\n\n* * *\n"
        #expect(has(text, .rule, "---"))
        #expect(has(text, .rule, "* * *"))
    }

    @Test func frontMatterIsNotARule() {
        let text = "---\ntitle: x\n---\n# H"
        let spans = kinds(text)
        #expect(spans.filter { $0.0 == .frontMatter }.map(\.1) == ["---", "title: x", "---"])
        #expect(!spans.contains { $0.0 == .rule })
        #expect(has(text, .heading, "# H"))
    }

    private func token(_ text: String, _ index: Int = 0) -> MarkdownHighlighter.Token {
        MarkdownHighlighter.tokens(in: text)[index]
    }

    private func markers(_ token: MarkdownHighlighter.Token, in text: String) -> [String] {
        token.markers.map { (text as NSString).substring(with: $0) }
    }

    @Test func headingTokensCarryLevelAndPrefix() {
        let text = "### Title **x**"
        let heading = token(text)
        #expect(heading.kind == .heading(level: 3))
        #expect(markers(heading, in: text) == ["### "])
        #expect(token(text, 1).kind == .strong)
    }

    @Test func inlineTokensListTheirDelimiters() {
        let text = "**b** *e* ~~s~~ ``c`` [t](https://x/y \"title\") ![a](i.png) <https://a.b>"
        let tokens = MarkdownHighlighter.tokens(in: text)
        #expect(tokens.map(\.kind) == [.strong, .emphasis, .strikethrough, .inlineCode, .link(destination: "https://x/y"), .image, .autolink(destination: "https://a.b")])
        #expect(markers(tokens[0], in: text) == ["**", "**"])
        #expect(markers(tokens[1], in: text) == ["*", "*"])
        #expect(markers(tokens[2], in: text) == ["~~", "~~"])
        #expect(markers(tokens[3], in: text) == ["``", "``"])
        #expect(markers(tokens[4], in: text) == ["[", "](https://x/y \"title\")"])
        #expect(markers(tokens[5], in: text) == ["![", "](i.png)"])
        #expect(markers(tokens[6], in: text) == ["<", ">"])
    }

    @Test func listItemsReportTheBullet() {
        #expect(token("  - [ ] task").kind == .listItem(bullet: 2))
        #expect(token("1. item").kind == .listItem(bullet: nil))
        #expect(("* item *em*" as NSString).substring(with: token("* item *em*", 1).range) == "*em*")
    }

    @Test func quotesCarryDepthAndInlineContent() {
        let text = "> > deep **b**"
        let quote = token(text)
        #expect(quote.kind == .quote(depth: 2))
        #expect(markers(quote, in: text) == ["> ", "> "])
        #expect(token(text, 1).kind == .strong)
        #expect(has(text, .quote, "> > deep **b**") && has(text, .strong, "**b**"))
    }

    @Test func rulesAndFencesHideTheirMarkers() {
        let text = "\n---\n```swift\nlet x = 1\n```"
        let tokens = MarkdownHighlighter.tokens(in: text)
        #expect(tokens.map(\.kind) == [.rule, .fence, .code, .fence])
        #expect(markers(tokens[0], in: text) == ["---"])
        #expect(markers(tokens[1], in: text) == ["```"])
        #expect(tokens[2].markers.isEmpty && markers(tokens[3], in: text) == ["```"])
    }

    @Test func strikethroughIsColored() {
        #expect(has("a ~~gone~~ b", .strikethrough, "~~gone~~"))
    }

    @Test func plainTextHasNoSpans() {
        #expect(MarkdownHighlighter.spans(in: "just words here\nand more").isEmpty)
        #expect(MarkdownHighlighter.spans(in: "").isEmpty)
    }
}
