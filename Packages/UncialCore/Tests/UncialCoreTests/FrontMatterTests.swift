import Testing
@testable import UncialCore

@Suite struct FrontMatterTests {
    @Test func splitsLeadingBlock() {
        let (frontMatter, body) = FrontMatter.split("---\ntitle: X\ntags: [a]\n---\n# Hi\n")
        #expect(frontMatter == "title: X\ntags: [a]")
        #expect(body == "# Hi\n")
    }

    @Test func ignoresWithoutClosingDelimiter() {
        let text = "---\nnot front matter\n# Hi"
        let (frontMatter, body) = FrontMatter.split(text)
        #expect(frontMatter == nil)
        #expect(body == text)
    }

    @Test func ignoresWhenNotAtStart() {
        #expect(FrontMatter.split("# Hi\n---\nx: 1\n---\n").frontMatter == nil)
    }

    @Test func acceptsDotsClosingAndCRLF() {
        let (frontMatter, body) = FrontMatter.split("---\r\na: 1\r\n...\r\nBody")
        #expect(frontMatter == "a: 1")
        #expect(body == "Body")
    }

    @Test func stripsBOM() {
        #expect(FrontMatter.split("\u{FEFF}---\na: 1\n---\n").frontMatter == "a: 1")
    }

    @Test func rendersNonEmptyBlockEscaped() {
        #expect(FrontMatter.renderBlock("a: <b>") == "<pre class=\"front-matter\">a: &lt;b&gt;</pre>\n")
        #expect(FrontMatter.renderBlock("  \n") == "")
    }
}
