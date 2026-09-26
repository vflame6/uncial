import Testing
@testable import UncialCore

@Suite struct HeadingAnchorsTests {
    @Test func slugFollowsGitHubRules() {
        #expect(HeadingAnchors.slug(for: "Hello, World!") == "hello-world")
        #expect(HeadingAnchors.slug(for: "C &amp; D") == "c--d")
        #expect(HeadingAnchors.slug(for: "<code>foo_bar</code> baz") == "foo_bar-baz")
        #expect(HeadingAnchors.slug(for: "Привет мир") == "привет-мир")
        #expect(HeadingAnchors.slug(for: "1.2 Release") == "12-release")
    }

    @Test func addsIDsAndDeduplicates() {
        let html = "<h1>Intro</h1>\n<h2>Setup</h2>\n<h2>Setup</h2>\n<h3 class=\"x\">Setup</h3>\n"
        let output = HeadingAnchors.addIDs(to: html)
        #expect(output.contains("<h1 id=\"intro\">Intro</h1>"))
        #expect(output.contains("<h2 id=\"setup\">Setup</h2>"))
        #expect(output.contains("<h2 id=\"setup-1\">Setup</h2>"))
        #expect(output.contains("<h3 id=\"setup-2\" class=\"x\">Setup</h3>"))
    }

    /// GitHub records every id it gives out and counts on until one is free: `# A`, `# A`, `# A-1` are
    /// a, a-1 and a-1-1, not a second a-1 that sends in-page links to the wrong heading.
    @Test func deduplicatesAgainstEveryIDGiven() {
        #expect(HeadingAnchors.addIDs(to: "<h1>A</h1><h1>A</h1><h1>A-1</h1>") == "<h1 id=\"a\">A</h1><h1 id=\"a-1\">A</h1><h1 id=\"a-1-1\">A-1</h1>")
        #expect(HeadingAnchors.addIDs(to: "<h2 id=\"b\">X</h2><h2>B</h2>") == "<h2 id=\"b\">X</h2><h2 id=\"b-1\">B</h2>")
    }

    @Test func keepsExistingIDs() {
        let html = "<h2 id=\"custom\">Title</h2>"
        #expect(HeadingAnchors.addIDs(to: html) == html)
    }
}
