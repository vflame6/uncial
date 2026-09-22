import Testing
@testable import UncialCore

@Suite struct CalloutsTests {
    @Test func defaultTypesAliasesAndRoles() {
        #expect(Callouts.kinds.map(\.name) == ["note", "abstract", "info", "todo", "tip", "success", "question", "warning", "failure", "danger", "bug", "example", "quote"])
        #expect(Callouts.type(for: "Hint") == "tip")
        #expect(Callouts.type(for: "TLDR") == "abstract")
        #expect(Callouts.type(for: "cite") == "quote")
        #expect(Callouts.type(for: "error") == "danger")
        #expect(Callouts.type(for: "Custom-Thing") == "custom-thing")
        #expect(Callouts.role(for: "info") == .note && Callouts.role(for: "todo") == .note)
        #expect(Callouts.role(for: "abstract") == .tip && Callouts.role(for: "tip") == .tip)
        #expect(Callouts.role(for: "failure") == .danger && Callouts.role(for: "bug") == .danger)
        #expect(Callouts.role(for: "custom") == .note)
        for kind in Callouts.kinds {
            #expect(Callouts.icon(for: kind.name).hasPrefix("<svg "), "\(kind.name)")
            #expect(Callouts.icon(for: kind.name).contains("stroke=\"currentColor\""), "\(kind.name)")
        }
        #expect(Callouts.icon(for: "custom") == Callouts.icon(for: "note"))
        #expect(Callouts.icon(for: "danger").contains("lucide-zap") == false && Callouts.icon(for: "danger") != Callouts.icon(for: "failure"))
        #expect(Callouts.foldIcon.hasPrefix("<svg "))
    }

    @Test func parsesMarkers() throws {
        let plain = try #require(Callouts.marker(in: "[!note] Title here  "))
        #expect(plain.identifier == "note" && plain.type == "note" && plain.fold == nil && plain.title == "Title here" && plain.length == 8)
        let folded = try #require(Callouts.marker(in: "[!Tip]- "))
        #expect(folded.type == "tip" && folded.fold == .closed && folded.title == "" && folded.length == 8 && folded.defaultTitle == "Tip")
        let open = try #require(Callouts.marker(in: "[!FAQ]+"))
        #expect(open.type == "question" && open.fold == .open && open.defaultTitle == "Faq" && open.length == 7)
        #expect(Callouts.defaultTitle(for: "NOTE") == "Note")
        #expect(Callouts.marker(in: "[!note]Title") == nil)
        #expect(Callouts.marker(in: "text [!note]") == nil)
        #expect(Callouts.marker(in: "[!]") == nil)
        #expect(Callouts.marker(in: "[note] x") == nil)
    }

    @Test func rendersABlockquoteWithAMarkerAsACallout() {
        let html = Callouts.render("<blockquote>\n<p>[!note] Title\nbody</p>\n</blockquote>\n")
        let expected = """
        <div class="callout" data-callout="note">
        <p class="callout-title"><span class="callout-icon">\(Callouts.icon(for: "note"))</span><span class="callout-title-text">Title</span></p>
        <div class="callout-content">
        <p>body</p>
        </div>
        </div>

        """
        #expect(html == expected)
    }

    @Test func titleFallsBackAliasesMapAndTitleOnlyHasNoContent() {
        let html = Callouts.render("<blockquote>\n<p>[!HINT]</p>\n</blockquote>\n")
        #expect(html.contains("<div class=\"callout\" data-callout=\"tip\">"))
        #expect(html.contains("<span class=\"callout-title-text\">Hint</span>"))
        #expect(!html.contains("callout-content"))
        let styled = Callouts.render("<blockquote>\n<p>[!warning] Mind the <em>gap</em></p>\n<ul>\n<li>one</li>\n</ul>\n</blockquote>\n")
        #expect(styled.contains("<span class=\"callout-title-text\">Mind the <em>gap</em></span>"))
        #expect(styled.contains("<div class=\"callout-content\">\n<ul>\n<li>one</li>\n</ul>\n</div>"))
    }

    @Test func foldableCalloutsBecomeDetails() {
        let closed = Callouts.render("<blockquote>\n<p>[!example]- More\ntext</p>\n</blockquote>\n")
        #expect(closed.hasPrefix("<details class=\"callout\" data-callout=\"example\">\n<summary class=\"callout-title\">"))
        #expect(closed.contains("<span class=\"callout-title-text\">More</span><span class=\"callout-fold\">\(Callouts.foldIcon)</span></summary>"))
        #expect(closed.hasSuffix("<div class=\"callout-content\">\n<p>text</p>\n</div>\n</details>\n"))
        let open = Callouts.render("<blockquote>\n<p>[!example]+ More</p>\n</blockquote>\n")
        #expect(open.hasPrefix("<details class=\"callout\" data-callout=\"example\" open>"))
    }

    @Test func nestedCalloutsAndPlainQuotesInside() {
        let html = Callouts.render("<blockquote>\n<p>[!question] Outer</p>\n<blockquote>\n<p>[!todo] Inner\nstep</p>\n</blockquote>\n<blockquote>\n<p>plain</p>\n</blockquote>\n</blockquote>\n")
        #expect(html.hasPrefix("<div class=\"callout\" data-callout=\"question\">"))
        #expect(html.contains("<div class=\"callout-content\">\n<div class=\"callout\" data-callout=\"todo\">"))
        #expect(html.contains("<p>step</p>"))
        #expect(html.contains("<blockquote>\n<p>plain</p>\n</blockquote>"))
        #expect(html.hasSuffix("</div>\n</div>\n"))
        #expect(html.components(separatedBy: "class=\"callout\"").count == 3)
    }

    @Test func leavesOtherBlockquotesAndTextAlone() {
        let quote = "<blockquote>\n<p>just a quote [!note]</p>\n</blockquote>\n<p>[!note] not a quote</p>\n"
        #expect(Callouts.render(quote) == quote)
        let heading = "<blockquote>\n<h2>Head</h2>\n<p>[!note] late</p>\n</blockquote>\n"
        #expect(Callouts.render(heading) == heading)
        #expect(Callouts.render("") == "")
    }

    @Test func keepsSourcePositionsAndMovesTheSplitParagraph() {
        let html = Callouts.render("<blockquote data-sourcepos=\"4:1-6:9\">\n<p data-sourcepos=\"4:3-6:9\">[!note] Title<br />\nbody\nmore</p>\n<p data-sourcepos=\"7:3-7:6\">last</p>\n</blockquote>\n")
        #expect(html.hasPrefix("<div class=\"callout\" data-callout=\"note\" data-sourcepos=\"4:1-6:9\">\n<p class=\"callout-title\">"))
        #expect(html.contains("<span class=\"callout-title-text\">Title</span></p>"))
        #expect(html.contains("<div class=\"callout-content\">\n<p data-sourcepos=\"5:1-6:9\">body\nmore</p>\n<p data-sourcepos=\"7:3-7:6\">last</p>\n</div>"))
    }
}
