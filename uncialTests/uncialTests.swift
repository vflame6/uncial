import Testing
import UniformTypeIdentifiers
@testable import Uncial

struct UncialTests {
    @Test func markdownTypeIsTheStandardIdentifier() {
        #expect(UTType.markdown.identifier == "net.daringfireball.markdown")
        #expect(UTType.markdownVariant.identifier == "com.maksimradaev.uncial.markdown")
        #expect(UTType.markdownVariant.conforms(to: .markdown))
        #expect(MarkdownDocument.readableContentTypes == [.markdown, .markdownVariant])
    }

    @Test func linkOpenerKnowsMarkdownExtensions() {
        #expect(LinkOpener.markdownExtensions.contains("md"))
        #expect(!LinkOpener.markdownExtensions.contains("txt"))
    }
}
