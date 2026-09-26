import Foundation
import Testing
@testable import UncialCore

@Suite struct MarkdownBlocksTests {
    private func kinds(_ markdown: String) -> [MarkdownBlocks.Kind?] {
        let blocks = MarkdownBlocks(markdown)
        let count = markdown.components(separatedBy: "\n").count
        return (0..<count).map { blocks.kind(ofLine: $0) }
    }

    @Test func fencedCodeWithItsFences() {
        #expect(kinds("a\n```js\nlet x\n```\nb") == [nil, .fenceOpening, .fencedCode, .fenceClosing, nil])
        // Unclosed: the block runs to the end of its container.
        #expect(kinds("```\ncode\nmore") == [.fenceOpening, .fencedCode, .fencedCode])
        // A fence inside a list item may be indented four spaces or more.
        #expect(kinds("- item\n\n    ```\n    *not em*\n    ```") == [nil, nil, .fenceOpening, .fencedCode, .fenceClosing])
    }

    /// A fence indented four spaces is content, and so the block stays open; a code line may start
    /// with ">"; blocks in a quote are the editor's (their lines carry the quote's prefixes).
    @Test func readsClosingAndQuotesAsCmarkDoes() {
        #expect(kinds("```\naaa\n    ```") == [.fenceOpening, .fencedCode, .fencedCode])
        #expect(kinds("```\n<\n >\n```") == [.fenceOpening, .fencedCode, .fencedCode, .fenceClosing])
        #expect(kinds("> ```\n> code\n> ```") == [nil, nil, nil])
    }

    @Test func indentedCode() {
        #expect(kinds("text\n\n    <a/>\n    *hi*\n\nafter") == [nil, nil, .indentedCode, .indentedCode, nil, nil])
        // Four spaces continuing a paragraph are not code.
        #expect(kinds("text\n    more") == [nil, nil])
    }

    @Test func htmlBlocksRunToABlankLine() {
        #expect(kinds("<div>\n*foo*\n\n*bar*") == [.html, .html, nil, nil])
        #expect(kinds("<p align=\"center\">\n  **Title**\n</p>\n\ntext") == [.html, .html, .html, nil, nil])
        // An inline tag inside a paragraph is not a block.
        #expect(kinds("a <b>c</b>") == [nil])
    }

    @Test func linesCountWithWindowsBreaksAndMultibyteText() {
        #expect(kinds("é\r\n```\r\nx\r\n```\r\nz".replacingOccurrences(of: "\r\n", with: "\n")) == [nil, .fenceOpening, .fencedCode, .fenceClosing, nil])
        let crlf = MarkdownBlocks("é\r\n```\r\nx\r\n```\r\nz")
        #expect((0..<5).map { crlf.kind(ofLine: $0) } == [nil, .fenceOpening, .fencedCode, .fenceClosing, nil])
    }
}
