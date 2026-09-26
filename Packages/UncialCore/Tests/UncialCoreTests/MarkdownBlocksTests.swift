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

    /// cmark's range for an HTML block closed by its end condition (`</script>`, `-->`, `</pre>`) stops a
    /// line short; its literal has every line.
    @Test func htmlBlocksKeepTheirClosingLine() {
        #expect(kinds("<script>\nfoo\n</script>1. *bar*\n\nafter") == [.html, .html, .html, nil, nil])
        #expect(kinds("<!--\nc\n-->\nafter") == [.html, .html, .html, nil])
        #expect(kinds("- <!--\n  c\n  -->\n- b") == [.html, .html, .html, nil])
        let crlf = MarkdownBlocks("<pre>\r\nx\r\n</pre>\r\nafter")
        #expect((0..<4).map { crlf.kind(ofLine: $0) } == [.html, .html, .html, nil])
    }

    /// Link reference definitions where cmark takes them: where a paragraph starts, or right after
    /// another definition; each with the lines it takes (BUG-28).
    @Test func linkDefinitionsWhereCmarkTakesThem() {
        typealias Definition = MarkdownBlocks.LinkDefinition
        func definitions(_ markdown: String) -> [Definition] {
            MarkdownBlocks(markdown).linkDefinitions
        }
        #expect(definitions("[foo]: /url \"title\"\n\n[foo]") == [Definition(label: "foo", destination: "/url", lines: 0...0)])
        // A destination or title may go on over the next lines, and another definition may follow.
        #expect(definitions("[a]:\n/a\n'one\ntwo'\n[b]: <b c>\n\ntext") == [
            Definition(label: "a", destination: "/a", lines: 0...3), Definition(label: "b", destination: "b c", lines: 4...4),
        ])
        // Right after a heading, and at the start of a paragraph that goes on after it.
        #expect(definitions("# Title\n[x]: /x\nand text") == [Definition(label: "x", destination: "/x", lines: 1...1)])
        // A title that fails on a line of its own leaves the definition before it.
        #expect(definitions("[foo]: /url\n\"title\" ok") == [Definition(label: "foo", destination: "/url", lines: 0...0)])
        // In a list item, from where its paragraph starts.
        #expect(definitions("- [a]: /a\n  text") == [Definition(label: "a", destination: "/a", lines: 0...0)])
        // Never inside a paragraph or code, never with more than a title after the destination.
        #expect(definitions("Foo\n[bar]: /baz").isEmpty)
        #expect(definitions("```\n[foo]: /url\n```").isEmpty)
        #expect(definitions("[foo]: <bar>(baz)").isEmpty)
        #expect(definitions("[foo]: /url 'title\n\nwith blank line'").isEmpty)
        #expect(definitions("[foo]: /url \"title\" ok").isEmpty)
        #expect(definitions("[^1]: /url\n\n[^1]").isEmpty)
    }

    /// The footnotes the page shows: defined and referenced.
    @Test func footnoteLabels() {
        #expect(MarkdownBlocks("a [^1] b [^2] c [^Big Note]\n\n[^1]: one\n[^3]: three\n[^big note]: four").footnoteLabels == ["1"])
        #expect(MarkdownBlocks("a [^x]\n\n[^x]: one").footnoteLabels == ["x"])
    }

    /// Lines break where cmark breaks them, at `\n`, `\r\n` and `\r`: a vertical tab (Word's line break),
    /// a form feed or U+2028 inside a line shifted every definition below it.
    @Test func linesBreakOnlyWhereCmarkBreaksThem() {
        for separator in ["\u{0B}", "\u{0C}", "\u{2028}", "\u{85}"] {
            let blocks = MarkdownBlocks("x\(separator)y\n\n[foo]: /url\n\n    code\n\n\nafter")
            #expect(blocks.linkDefinitions == [MarkdownBlocks.LinkDefinition(label: "foo", destination: "/url", lines: 2...2)])
            #expect((0..<8).map { blocks.kind(ofLine: $0) } == [nil, nil, nil, nil, .indentedCode, nil, nil, nil])
        }
    }

    @Test func linesCountWithWindowsBreaksAndMultibyteText() {
        #expect(kinds("é\r\n```\r\nx\r\n```\r\nz".replacingOccurrences(of: "\r\n", with: "\n")) == [nil, .fenceOpening, .fencedCode, .fenceClosing, nil])
        let crlf = MarkdownBlocks("é\r\n```\r\nx\r\n```\r\nz")
        #expect((0..<5).map { crlf.kind(ofLine: $0) } == [nil, .fenceOpening, .fencedCode, .fenceClosing, nil])
    }
}
