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

    @Test func emphasisNeedsFlankingTextAndNoEscape() {
        #expect(!has("2 * 3 * 4", .emphasis, "* 3 *"))
        #expect(!has("a ** b ** c", .strong, "** b **"))
        #expect(!has("\\*not italic\\*", .emphasis, "*not italic*"))
        #expect(!has("\\**not bold\\**", .strong, "**not bold**"))
        #expect(has("a *b* c", .emphasis, "*b*") && has("a _b_ c", .emphasis, "_b_"))
        #expect(has("a **b** c", .strong, "**b**") && has("(*x*)", .emphasis, "*x*"))
    }

    @Test func tripleAsterisksAreBoldItalic() {
        let text = "a ***bold italic*** c"
        #expect(has(text, .strong, "***bold italic***") && has(text, .emphasis, "bold italic"))
        let tokens = MarkdownHighlighter.tokens(in: text)
        #expect(tokens.map(\.kind) == [.strong, .emphasis])
        #expect(markers(tokens[0], in: text) == ["***", "***"] && tokens[1].markers.isEmpty)
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
        #expect(has("text\n---", .heading, "text"))
    }

    @Test func tablesAlignColumns() {
        let text = "| a | **b** |\n|:--|--:|\n| cc | d |\n"
        let tokens = MarkdownHighlighter.tokens(in: text)
        guard case .tableRow(let cells, let isHeader, let pipes) = tokens[0].kind else {
            Issue.record("no header row")
            return
        }
        #expect(isHeader && pipes == [0, 4, 12])
        #expect(cells.map { (text as NSString).substring(with: $0.range) } == [" a ", " **b** "])
        #expect(cells.map(\.visibleWidth) == [3, 3] && cells.map(\.columnWidth) == [4, 3])
        #expect(cells.map(\.alignment) == [.left, .right])
        #expect(markers(tokens[0], in: text) == ["|", "|"])
        #expect(tokens[1].kind == .strong)
        #expect(tokens[2].kind == .tableDelimiter && markers(tokens[2], in: text) == ["|:--|--:|"])
        guard case .tableRow(let body, let bodyHeader, _) = tokens[3].kind else {
            Issue.record("no body row")
            return
        }
        #expect(!bodyHeader && body.map(\.visibleWidth) == [4, 3] && body.map(\.columnWidth) == [4, 3])
        #expect(tokens.count == 4)
        #expect(has(text, .table, "|") && has(text, .table, "|:--|--:|"))
    }

    @Test func setextHeadings() {
        let text = "Title\n===\ntext *e*\n---\n\n---"
        let tokens = MarkdownHighlighter.tokens(in: text)
        #expect(tokens.map(\.kind) == [.heading(level: 1), .headingUnderline, .heading(level: 2), .emphasis, .headingUnderline, .rule])
        #expect(tokens[0].markers.isEmpty && markers(tokens[1], in: text) == ["==="])
        #expect(has(text, .heading, "Title") && has(text, .heading, "text *e*") && has(text, .rule, "==="))
    }

    @Test func footnotesAndHtml() {
        let text = "see[^1] and <b>x</b> <!-- c -->\n[^1]: note **b**"
        let tokens = MarkdownHighlighter.tokens(in: text)
        #expect(tokens.map(\.kind) == [.footnoteReference, .html, .html, .html, .footnoteDefinition, .strong])
        #expect(markers(tokens[0], in: text) == ["[^", "]"])
        #expect((text as NSString).substring(with: tokens[4].range) == "[^1]:")
        #expect(has(text, .link, "[^1]") && has(text, .html, "<b>") && has(text, .link, "[^1]:"))
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
        #expect(tokens.map(\.kind) == [.strong, .emphasis, .strikethrough, .inlineCode, .link(destination: "https://x/y"), .image(destination: "i.png"), .autolink(destination: "https://a.b")])
        #expect(markers(tokens[0], in: text) == ["**", "**"])
        #expect(markers(tokens[1], in: text) == ["*", "*"])
        #expect(markers(tokens[2], in: text) == ["~~", "~~"])
        #expect(markers(tokens[3], in: text) == ["``", "``"])
        #expect(markers(tokens[4], in: text) == ["[", "](https://x/y \"title\")"])
        #expect(markers(tokens[5], in: text) == ["![", "](i.png)"])
        #expect(markers(tokens[6], in: text) == ["<", ">"])
    }

    @Test func listItemsReportTheBullet() {
        #expect(token("  - [ ] task").kind == .listItem(bullet: 2, box: NSRange(location: 4, length: 3)))
        #expect(markers(token("  - [ ] task"), in: "  - [ ] task") == ["[", "]"])
        #expect(token("1. item").kind == .listItem(bullet: nil, box: nil))
        #expect(token("- plain").markers.isEmpty)
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
