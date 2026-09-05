import Foundation
import Testing
@testable import UncialCore

@Suite struct MarkdownTextTests {
    @Test func decodesUTF8AndStripsBOM() {
        #expect(MarkdownText.decode(Data([0xEF, 0xBB, 0xBF] + Array("# Hi".utf8))) == "# Hi")
        #expect(MarkdownText.decode(Data("# Hi".utf8)) == "# Hi")
    }

    @Test func decodesInvalidBytesLossily() {
        let text = MarkdownText.decode(Data([0x23, 0x20, 0xFF, 0xFE, 0x41]))
        #expect(text.hasPrefix("# "))
        #expect(text.hasSuffix("A"))
    }

    @Test func decodesUTF16WithBOM() {
        #expect(MarkdownText.decode("# Hi".data(using: .utf16)!) == "# Hi")
    }
}
