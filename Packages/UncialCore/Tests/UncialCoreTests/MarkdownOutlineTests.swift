import Testing
@testable import UncialCore

@Suite struct MarkdownOutlineTests {
    typealias Run = MarkdownOutline.Run

    @Test func headingsParagraphsAndInlineStyles() {
        let blocks = MarkdownOutline.blocks(in: "# Title\n\nSome **bold** and *soft*\ntext with `code` and [a link](x) ~~gone~~.\n")
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .heading(level: 1))
        #expect(blocks[0].text == "Title")
        #expect(blocks[1].kind == .paragraph)
        #expect(blocks[1].text == "Some bold and soft text with code and a link gone.")
        #expect(blocks[1].runs.contains(Run("bold", isStrong: true)))
        #expect(blocks[1].runs.contains(Run("soft", isEmphasis: true)))
        #expect(blocks[1].runs.contains(Run("code", isCode: true)))
        #expect(blocks[1].runs.contains(Run("a link", isLink: true)))
        #expect(blocks[1].runs.contains(Run("gone", isStrikethrough: true)))
    }

    @Test func listsCarryMarkersAndDepth() {
        let blocks = MarkdownOutline.blocks(in: "- one\n- two\n  1. nested\n  2. again\n- [x] done\n- [ ] todo\n\n3. third\n4. fourth\n")
        #expect(blocks.map(\.kind) == [
            .listItem(marker: "•"), .listItem(marker: "•"), .listItem(marker: "1."), .listItem(marker: "2."),
            .listItem(marker: "☑"), .listItem(marker: "☐"), .listItem(marker: "3."), .listItem(marker: "4."),
        ])
        #expect(blocks.map(\.listDepth) == [1, 1, 2, 2, 1, 1, 1, 1])
        #expect(blocks[2].text == "nested")
    }

    @Test func quotesCodeAndRules() {
        let blocks = MarkdownOutline.blocks(in: "> quoted\n>\n> > deeper\n\n```swift\nlet x = 1\n```\n\n---\n")
        #expect(blocks.map(\.kind) == [.paragraph, .paragraph, .code, .rule])
        #expect(blocks.map(\.quoteDepth) == [1, 2, 0, 0])
        #expect(blocks[2].runs == [Run("let x = 1\n", isCode: true)])
    }

    @Test func calloutsShowTheirTitleWithoutTheMarker() {
        let blocks = MarkdownOutline.blocks(in: "> [!tip] Hello **there**\n> body\n> more\n\n> [!NOTE]\n> only\n")
        #expect(blocks.map(\.kind) == [.paragraph, .paragraph, .paragraph, .paragraph])
        #expect(blocks.map(\.quoteDepth) == [1, 1, 1, 1])
        #expect(blocks[0].runs == [Run("Hello ", isStrong: true), Run("there", isStrong: true)])
        #expect(blocks[1].text == "body more")
        #expect(blocks[2].runs == [Run("Note", isStrong: true)])
        #expect(blocks[3].text == "only")
    }

    @Test func tablesBecomeRows() {
        let blocks = MarkdownOutline.blocks(in: "| a | b |\n|---|---|\n| 1 | **2** |\n")
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .tableRow(cells: [[Run("a")], [Run("b")]], isHeader: true))
        #expect(blocks[1].kind == .tableRow(cells: [[Run("1")], [Run("2", isStrong: true)]], isHeader: false))
    }

    @Test func imagesHtmlAndFrontMatter() {
        let blocks = MarkdownOutline.blocks(in: "---\ntitle: x\n---\n\n<div>raw</div>\n\n![alt text](a.png) ![](b.png)\n")
        #expect(blocks.count == 1)
        #expect(blocks[0].runs == [Run("alt text", isImage: true), Run(" "), Run("Image", isImage: true)])
    }

    @Test func stopsAtTheLimit() {
        let markdown = (1...50).map { "para \($0)" }.joined(separator: "\n\n")
        #expect(MarkdownOutline.blocks(in: markdown, limit: 7).count == 7)
        #expect(MarkdownOutline.blocks(in: "").isEmpty)
    }
}
