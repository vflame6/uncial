import Testing
import UniformTypeIdentifiers
@testable import Uncial

struct UncialTests {
    @Test func markdownTypeIsTheStandardIdentifier() {
        #expect(UTType.markdown.identifier == "net.daringfireball.markdown")
        #expect(MarkdownDocument.readableContentTypes == [.markdown])
    }

    @Test func linkOpenerKnowsMarkdownExtensions() {
        #expect(LinkOpener.markdownExtensions.contains("md"))
        #expect(!LinkOpener.markdownExtensions.contains("txt"))
    }
}
