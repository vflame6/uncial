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

    @Test func keepsExistingIDs() {
        let html = "<h2 id=\"custom\">Title</h2>"
        #expect(HeadingAnchors.addIDs(to: html) == html)
    }
}
