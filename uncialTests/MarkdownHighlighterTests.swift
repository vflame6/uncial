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

    /// Front matter, fenced code (fences included) and `$$` blocks are literal text, one range per
    /// block; display math on an ordinary line is not.
    @Test func literalBlocksCoverFencesMathAndFrontMatter() {
        let text = "---\ntags:\n  - a\n---\n- item\n```yaml\n  - \n```\n$$\nx^2\n$$\nsee $$y$$\n~~~\nopen"
        let ranges = MarkdownHighlighter.literalBlocks(in: MarkdownHighlighter.tokens(in: text))
        let blocks = ranges.map { (text as NSString).substring(with: $0) }
        #expect(blocks == ["---\ntags:\n  - a\n---", "```yaml\n  - \n```", "$$\nx^2\n$$", "~~~\nopen"])
    }

    /// CommonMark's fence rules: a backtick fence's info string has no backticks, so a line of inline
    /// code that starts with three of them opens nothing; a closing fence has no info string, so ```js
    /// inside an open block is content (spec examples 115 and 117). The rest of the document used to
    /// become one code block.
    @Test func fencesFollowTheInfoStringRules() {
        let inline = "```npm install```\nNext paragraph with **bold**"
        #expect(kinds(inline).filter { $0.0 == .codeBlock }.isEmpty)
        #expect(has(inline, .strong, "**bold**"))
        let span = "```` ```mermaid ````\n- item"
        #expect(kinds(span).filter { $0.0 == .codeBlock }.isEmpty)
        #expect(has(span, .listMarker, "- "))
        let nested = "```md\n```js\nstill code\n```\nafter *em*"
        #expect(kinds(nested).filter { $0.0 == .codeBlock }.map(\.1) == ["```md", "```js", "still code", "```"])
        #expect(has(nested, .emphasis, "*em*"))
        let tilde = "~~~ aa ``` ~~~\nfoo\n~~~  \nbar *em*"
        #expect(kinds(tilde).filter { $0.0 == .codeBlock }.map(\.1) == ["~~~ aa ``` ~~~", "foo", "~~~  "])
        #expect(has(tilde, .emphasis, "*em*"))
    }

    /// Code and HTML blocks as cmark reads them: indented code, and a fence indented inside a list item,
    /// are code with no Markdown in them; an HTML block's Markdown stays as written, only its tags are
    /// read. Live Preview hid `**` and `__init__` there, which the page shows (BUG-24, BUG-28).
    @Test func codeAndHTMLBlocksComeFromCmark() {
        let indented = "text\n\n    **not bold** __init__\n\nafter *em*"
        #expect(kinds(indented).filter { $0.0 == .codeBlock }.map(\.1) == ["    **not bold** __init__"])
        #expect(!has(indented, .strong, "**not bold**") && has(indented, .emphasis, "*em*"))
        let listed = "- item\n\n    ```py\n    x = *y*\n    ```"
        #expect(kinds(listed).filter { $0.0 == .codeBlock }.map(\.1) == ["    ```py", "    x = *y*", "    ```"])
        let html = "<p align=\"center\">\n  **Title**\n</p>\n\n**bold**"
        let tokens = MarkdownHighlighter.tokens(in: html)
        #expect(!tokens.contains { $0.kind == .strong && $0.range.location < 30 })
        #expect(has(html, .strong, "**bold**"))
        #expect(tokens.contains { if case .html = $0.kind { return true }; return false })
    }

    @Test func tildeFencesAndLongerClosersWork() {
        let text = "~~~\n```\nstill code\n~~~~\ndone"
        #expect(kinds(text).filter { $0.0 == .codeBlock }.count == 4)
        #expect(!has(text, .codeBlock, "done"))
    }

    /// Emphasis follows CommonMark's flanking rules: a run opens only before text (`a**"foo"**` is no
    /// emphasis), `_` never inside a word (`foo__bar__`, `__foo__bar`), no delimiter pairs across a link's
    /// text, and GFM's `~~` the same (`~~ spaced ~~` is not struck). Live Preview hid those markers, which
    /// the page shows (BUG-28).
    @Test func emphasisFollowsTheFlankingRules() {
        for text in ["a**\"foo\"**", "a__\"foo\"__", "foo__bar__", "5__6__78", "__foo__bar", "**(**foo)", "__(__foo)", "_foo [bar_](/url)", "~~ spaced ~~"] {
            let emphasis = MarkdownHighlighter.tokens(in: text).filter { [.strong, .emphasis, .strikethrough].contains($0.kind) }
            #expect(emphasis.isEmpty, "\(text)")
        }
        #expect(has("**bold** and *em* and __under__ and ~~gone~~", .strong, "**bold**"))
        #expect(has("x *em*, y", .emphasis, "*em*"))
        #expect(has("(*em*)", .emphasis, "*em*"))
        #expect(has("a ~~gone~~ b", .strikethrough, "~~gone~~"))
    }

    @Test func inlineCodeMasksEmphasis() {
        let text = "`a*b*c` *d*"
        #expect(has(text, .inlineCode, "`a*b*c`"))
        #expect(has(text, .emphasis, "*d*"))
        #expect(!has(text, .emphasis, "*b*"))
    }

    /// Code spans as CommonMark reads them: a run of backticks closes at the next run of the same
    /// length, and shorter or longer runs between are code (spec examples 339, 349, 350, 357 and 359).
    /// Runs of different lengths used to pair, so `` `ls` `` showed as " ls ".
    @Test func codeSpansCloseWithAnEqualRun() {
        let text = "Use `` `ls` `` to list"
        let tokens = MarkdownHighlighter.tokens(in: text)
        #expect(tokens.map(\.kind) == [.inlineCode])
        #expect(tokens.map { (text as NSString).substring(with: $0.range) } == ["`` `ls` ``"])
        #expect(tokens.first.map { markers($0, in: text) } == ["``", "``"])
        #expect(MarkdownHighlighter.tokens(in: "`a``b`").map { ("`a``b`" as NSString).substring(with: $0.range) } == ["`a``b`"])
        #expect(MarkdownHighlighter.tokens(in: "``unclosed`").isEmpty)
        #expect(MarkdownHighlighter.tokens(in: "\\`not code`").map(\.kind) == [.escape])
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
        #expect(tokens.map(\.kind) == [.footnoteReference, .html(element: "b", attributes: [:]), .html(element: nil, attributes: [:]), .footnoteDefinition, .strong])
        #expect(markers(tokens[1], in: text) == ["<b>", "</b>"] && markers(tokens[2], in: text) == ["<!-- c -->"])
        #expect(markers(tokens[0], in: text) == ["[^", "]"])
        #expect((text as NSString).substring(with: tokens[3].range) == "[^1]:")
        #expect(has(text, .link, "[^1]") && has(text, .html, "<b>") && has(text, .link, "[^1]:"))
    }

    @Test func htmlTagsBecomeMarkersAndImages() {
        let text = "a <br> <img src=\"i.png\" alt=\"i\"> <div align=\"center\">x</div> <a href='u'>t</a> <i><b>n</b></i> </p>"
        let tokens = MarkdownHighlighter.tokens(in: text)
        #expect(tokens.map(\.kind) == [
            .html(element: "br", attributes: [:]), .image(destination: "i.png"),
            .html(element: "div", attributes: ["align": "center"]), .html(element: "a", attributes: ["href": "u"]),
            .html(element: "i", attributes: [:]), .html(element: "b", attributes: [:]), .html(element: "p", attributes: [:]),
        ])
        #expect(markers(tokens[0], in: text) == ["<br>"])
        #expect(markers(tokens[1], in: text) == ["<img src=\"i.png\" alt=\"i\">"])
        #expect(markers(tokens[2], in: text) == ["<div align=\"center\">", "</div>"])
        #expect(markers(tokens[4], in: text) == ["<i>", "</i>"] && markers(tokens[5], in: text) == ["<b>", "</b>"])
        #expect(markers(tokens[6], in: text) == ["</p>"])
        #expect(has(text, .html, "<div align=\"center\">") && has(text, .html, "</div>") && !has(text, .html, "x"))
    }

    /// Inline links read as CommonMark reads them: a badge is a link around an image; a destination may
    /// hold balanced parentheses or, in `<…>`, spaces; a bare destination with a space is no link. Live
    /// Preview used to show badges and Wikipedia links as broken text and ⌘-click the wrong target.
    @Test func inlineLinksReadDestinationsLikeCommonMark() throws {
        let badge = "[![Build](https://img.shields.io/b.svg)](https://github.com/o/r/actions) text"
        let tokens = MarkdownHighlighter.tokens(in: badge)
        #expect(tokens.map(\.kind) == [.link(destination: "https://github.com/o/r/actions"), .image(destination: "https://img.shields.io/b.svg")])
        try #require(tokens.count == 2)
        #expect(markers(tokens[0], in: badge) == ["[", "](https://github.com/o/r/actions)"])
        #expect(markers(tokens[1], in: badge) == ["![", "](https://img.shields.io/b.svg)"])
        let wiki = "[Mercury](https://en.wikipedia.org/wiki/Mercury_(planet)) rest"
        #expect(MarkdownHighlighter.tokens(in: wiki).map(\.kind) == [.link(destination: "https://en.wikipedia.org/wiki/Mercury_(planet)")])
        #expect(MarkdownHighlighter.tokens(in: "![pic](<my image.png>)").map(\.kind) == [.image(destination: "my image.png")])
        #expect(MarkdownHighlighter.tokens(in: "[link](/my uri)").isEmpty)
        let titled = "[a](http://x.com 'T') and [b](<c d> (T))"
        #expect(MarkdownHighlighter.tokens(in: titled).map(\.kind) == [.link(destination: "http://x.com"), .link(destination: "c d")])
        let nested = "[a [b](c) d](e)"
        #expect(MarkdownHighlighter.tokens(in: nested).map(\.kind) == [.link(destination: "c")])
    }

    /// Definitions as CommonMark reads them: none inside code, none interrupting a paragraph, nothing but
    /// a title after the destination; and a footnote reference needs its definition. Live Preview made
    /// links of brackets the page shows as text (BUG-28; spec examples 166, 170, 181, 182).
    /// cmark's lines break at `\n`, `\r\n` and `\r` only; the editor's also at U+2028, U+2029 and U+0085.
    /// Blocks keep to their lines either way.
    @Test func blocksKeepToTheirLinesAcrossUnicodeSeparators() {
        for separator in ["\u{2028}", "\u{2029}", "\u{85}", "\u{0B}"] {
            let text = "a\(separator)b\n\n    code\n\n[x]: /x\n\n*e* [x]"
            let tokens = MarkdownHighlighter.tokens(in: text)
            #expect(tokens.map(\.kind) == [.code, .linkDefinition, .emphasis, .link(destination: "/x")])
            #expect(tokens.prefix(2).map { (text as NSString).substring(with: $0.range) } == ["    code", "[x]: /x"])
        }
    }

    @Test func definitionsFollowCommonMark() {
        func references(_ text: String) -> [MarkdownHighlighter.Token.Kind] {
            MarkdownHighlighter.tokens(in: text).map(\.kind).filter {
                if case .link = $0 { return true }
                return $0 == .footnoteReference
            }
        }
        #expect(references("```\n[foo]: /url\n```\n\n[foo]").isEmpty)
        #expect(references("Foo\n[bar]: /baz\n\n[bar]").isEmpty)
        #expect(references("[foo]: <bar>(baz)\n\n[foo]").isEmpty)
        #expect(references("[foo]: /url 'title\n\nwith blank line'\n\n[foo]").isEmpty)
        #expect(references("[foo]: /url \"T\"\n\n[foo]") == [.link(destination: "/url")])
        #expect(references("# Title\n[foo]: /url\n\n[foo]") == [.link(destination: "/url")])
        #expect(references("see [^1] and [^2]\n\n[^1]: note") == [.footnoteReference])
        // In a list item the definition follows the marker, and is no link itself.
        let item = MarkdownHighlighter.tokens(in: "- [foo]: /url\n  text\n\n[foo]")
        #expect(item.map(\.kind) == [.listItem(bullet: 0, box: nil), .linkDefinition, .link(destination: "/url")])
    }

    @Test func referenceLinksResolveAgainstDefinitions() {
        let text = "[one][Ref] and [two][] and [Three] but [none][x] and ![pic][img]\n\n[ref]: https://a.example\n[two]: /b\n[three]: <c d> 'T'\n[img]: i.png"
        let tokens = MarkdownHighlighter.tokens(in: text)
        #expect(tokens.map(\.kind) == [
            .link(destination: "https://a.example"), .link(destination: "/b"), .link(destination: "c d"), .image(destination: "i.png"),
            .linkDefinition, .linkDefinition, .linkDefinition, .linkDefinition,
        ])
        #expect(markers(tokens[0], in: text) == ["[", "][Ref]"])
        #expect(markers(tokens[1], in: text) == ["[", "][]"])
        #expect(markers(tokens[2], in: text) == ["[", "]"])
        #expect(markers(tokens[3], in: text) == ["![", "][img]"])
        #expect((text as NSString).substring(with: tokens[4].range) == "[ref]: https://a.example")
        #expect(has(text, .link, "[one]") && has(text, .url, "[Ref]") && has(text, .link, "[img]: i.png"))
    }

    @Test func escapesHideTheBackslash() {
        let text = "3 \\* 4 and \\[x] and \\\\ but a\\b"
        let tokens = MarkdownHighlighter.tokens(in: text)
        #expect(tokens.map(\.kind) == [.escape, .escape, .escape])
        #expect(tokens.map { markers($0, in: text) } == [["\\"], ["\\"], ["\\"]])
        #expect((text as NSString).substring(with: tokens[1].range) == "\\[")
    }

    @Test func mathHidesItsDollars() {
        let text = "Euler $e^{i\\pi}$ costs $5 and $10; $$\\int x$$ and *a $b*c$ d*\n$$\nx = 1\n$$"
        let tokens = MarkdownHighlighter.tokens(in: text)
        #expect(tokens.map(\.kind) == [.math(display: false), .math(display: true), .emphasis, .math(display: false), .mathFence, .math(display: true), .mathFence])
        #expect(markers(tokens[0], in: text) == ["$", "$"] && markers(tokens[1], in: text) == ["$$", "$$"])
        #expect((text as NSString).substring(with: tokens[3].range) == "$b*c$")
        #expect(markers(tokens[4], in: text) == ["$$"] && (text as NSString).substring(with: tokens[5].range) == "x = 1")
        #expect(has(text, .math, "$e^{i\\pi}$") && has(text, .math, "x = 1"))
    }

    @Test func frontMatterIsNotARule() {
        let text = "---\ntitle: x\n---\n# H"
        let spans = kinds(text)
        #expect(spans.filter { $0.0 == .frontMatter }.map(\.1) == ["---", "title: x", "---"])
        #expect(!spans.contains { $0.0 == .rule })
        #expect(has(text, .heading, "# H"))
    }

    /// Raw HTML as cmark reads it: a bad attribute name, an unclosed quote, attributes without space
    /// between them or on a closing tag make text; `<!-->` is a whole comment; processing instructions,
    /// declarations and CDATA are HTML; GFM's tag filter shows `<title>`, `<style>`, `<script>` and the
    /// like as text.
    @Test func rawHTMLFollowsCommonMark() {
        func hidden(_ text: String) -> [String] {
            MarkdownHighlighter.tokens(in: text).flatMap(\.markers).map { (text as NSString).substring(with: $0) }
        }
        #expect(hidden("<a h*#ref=\"hi\">").isEmpty)
        #expect(hidden("<a href=\"hi'> <a href=hi'>").isEmpty)
        #expect(hidden("<a href='bar'title=title>").isEmpty)
        #expect(hidden("</a href=\"foo\">").isEmpty)
        #expect(hidden("foo <!--> foo -->") == ["<!-->"])
        #expect(hidden("foo <!---> foo -->") == ["<!--->"])
        #expect(hidden("<strong> <title> <style> <em>") == ["<strong>", "<em>"])
        #expect(hidden("<script>alert(1)</script> <IFRAME src=x></iframe>").isEmpty)
        #expect(hidden("<a href='x' title=\"y\" data-z=1 disabled>t</a>") == ["<a href='x' title=\"y\" data-z=1 disabled>", "</a>"])
        #expect(hidden("a <?php echo 1; ?> <!DOCTYPE html> <![CDATA[x]]> b") == ["<?php echo 1; ?>", "<!DOCTYPE html>", "<![CDATA[x]]>"])
        // A closing tag passed over leaves a tag inside its quotes to be read.
        #expect(hidden("</a title=\"<b>\">") == ["<b>"])
    }

    /// Front matter as the page reads it: only when it closes (an unclosed `---` is a rule and the
    /// text below it Markdown), and behind a byte order mark too.
    @Test func frontMatterOnlyWhenItCloses() {
        #expect(MarkdownHighlighter.tokens(in: "---\n# Title\ntext *e*").map(\.kind) == [.rule, .heading(level: 1), .emphasis])
        #expect(MarkdownHighlighter.tokens(in: "\u{FEFF}---\ntitle: x\n---\n# H").map(\.kind) == [.frontMatter, .frontMatter, .frontMatter, .heading(level: 1)])
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

    @Test func calloutsOpenWhereTheirBlockquoteBegins() {
        let text = "> [!Note] Title **b**\n> body\n\n> [!tip]-\n> x\n> > [!todo] nested\n> a\n> [!note] late"
        let tokens = MarkdownHighlighter.tokens(in: text)
        let first = token(text)
        #expect(first.kind == .callout(type: "note", depth: 1, defaultTitle: "Note"))
        #expect(markers(first, in: text) == ["> ", "[!Note] "])
        #expect(has(text, .callout, "[!Note] ") && has(text, .quote, "> [!Note] Title **b**") && has(text, .strong, "**b**"))
        #expect(token(text, 2).kind == .quote(depth: 1))
        let folded = tokens.first { $0.range.location == 30 }
        #expect(folded?.kind == .callout(type: "tip", depth: 1, defaultTitle: "Tip"))
        #expect(folded.map { markers($0, in: text) } == ["> ", "[!tip]-"])
        let nested = tokens.first { $0.range.location == 44 }
        #expect(nested?.kind == .callout(type: "todo", depth: 2, defaultTitle: "Todo"))
        #expect(nested.map { markers($0, in: text) } == ["> ", "> ", "[!todo] "])
        // A marker on a line that continues a blockquote is plain text.
        #expect(tokens.first { $0.range.location == 67 }?.kind == .quote(depth: 1))
        #expect(!has("> a\n> [!note] b", .callout, "[!note] "))
        #expect(has(">   [!x] spaced", .callout, "[!x] "))
        #expect(!has("> [!note]x", .callout, "[!note]"))

        let blocks = MarkdownHighlighter.calloutBlocks(in: tokens, text: text as NSString)
        #expect(blocks.map(\.range) == [NSRange(location: 0, length: 28), NSRange(location: 30, length: 51), NSRange(location: 44, length: 18)])
        #expect(blocks.map(\.type) == ["note", "tip", "todo"] && blocks.map(\.depth) == [1, 1, 2])
        #expect(MarkdownHighlighter.calloutBlocks(in: MarkdownHighlighter.tokens(in: "> [!note]\n> a\nlazy\n> b"), text: "> [!note]\n> a\nlazy\n> b").map(\.range) == [NSRange(location: 0, length: 13)])
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
