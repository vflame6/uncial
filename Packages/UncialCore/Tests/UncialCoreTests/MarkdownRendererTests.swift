import Foundation
import Testing
@testable import UncialCore

@Suite struct MarkdownRendererTests {
    let renderer = MarkdownRenderer()

    @Test func rendersGitHubExtensions() {
        let markdown = """
        | a | b |
        |---|---|
        | 1 | 2 |

        - [x] done
        - [ ] todo

        ~~gone~~ see www.example.com
        """
        let html = renderer.renderBody(markdown)
        #expect(html.contains("<table>"))
        #expect(html.contains("<input type=\"checkbox\" checked=\"\" disabled=\"\" />"))
        #expect(html.contains("<del>gone</del>"))
        #expect(html.contains("<a href=\"http://www.example.com\">www.example.com</a>"))
    }

    @Test func filtersDangerousRawHTMLButKeepsSafeHTML() {
        let html = renderer.renderBody("<script>alert(1)</script>\n\n<details><summary>More</summary>Body</details>")
        #expect(html.contains("&lt;script>"))
        #expect(!html.contains("<script>"))
        #expect(html.contains("<details><summary>More</summary>Body</details>"))
    }

    @Test func emptyInputProducesEmptyBody() {
        #expect(renderer.renderBody("") == "")
    }

    @Test func rendersFootnotesWithClosedBackref() {
        let html = renderer.renderBody("Note[^1]\n\n[^1]: Footnote text\n")
        #expect(html.contains("<section class=\"footnotes\""))
        #expect(html.contains("aria-label=\"Back to reference 1\">↩</a>"))
    }

    @Test func rendersFrontMatterAsBlock() {
        let html = renderer.renderBody("---\ntitle: Hi\n---\n# Body")
        #expect(html.hasPrefix("<pre class=\"front-matter\">title: Hi</pre>"))
        #expect(html.contains("<h1 id=\"body\">Body</h1>"))
    }

    @Test func rendersHeadingWithAnchor() {
        #expect(renderer.renderBody("# Hello World").contains("<h1 id=\"hello-world\">Hello World</h1>"))
    }

    @Test func documentWrapsBodyWithStyleAndTitle() {
        let html = renderer.renderDocument("# T", title: "A <B> & C.md")
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<meta name=\"color-scheme\" content=\"light dark\">"))
        #expect(html.contains("<title>A &lt;B&gt; &amp; C.md</title>"))
        #expect(html.contains("<style>"))
        #expect(html.contains("prefers-color-scheme: dark"))
        #expect(html.contains("<article class=\"markdown-body\">\n<h1 id=\"t\">T</h1>"))
    }

    @Test func documentInlinesImagesRelativeToBaseURL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uncial-doc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x47, 0x49, 0x46]).write(to: directory.appendingPathComponent("a.gif"))
        let html = renderer.renderDocument("![a](a.gif)", title: "t", baseURL: directory.appendingPathComponent("doc.md"))
        #expect(html.contains("<img src=\"data:image/gif;base64,R0lG\" alt=\"a\" />"))
    }
}
