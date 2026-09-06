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

    @Test func plainTextHasNoSpans() {
        #expect(MarkdownHighlighter.spans(in: "just words here\nand more").isEmpty)
        #expect(MarkdownHighlighter.spans(in: "").isEmpty)
    }
}
