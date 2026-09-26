import Foundation
import Testing
@testable import UncialCore

@Suite struct MarkdownTextTests {
    @Test func decodesUTF8AndStripsBOM() {
        #expect(MarkdownText.decode(Data([0xEF, 0xBB, 0xBF] + Array("# Hi".utf8))) == "# Hi")
        #expect(MarkdownText.decode(Data("# Hi".utf8)) == "# Hi")
    }

    @Test func decodesUTF16WithBOM() {
        #expect(MarkdownText.decode("# Hi".data(using: .utf16)!) == "# Hi")
    }

    /// UTF-8, BOM-marked UTF-8 and UTF-16 files are written back as plain UTF-8 (a design decision:
    /// every character is kept).
    @Test func savesUnicodeFilesAsUTF8() {
        #expect(MarkdownText.read(Data("# Hi".utf8)) == MarkdownText.Decoded(text: "# Hi", encoding: .utf8, isLossy: false))
        #expect(MarkdownText.read(Data([0xEF, 0xBB, 0xBF] + Array("# Hi".utf8))).encoding == .utf8)
        #expect(MarkdownText.read("# Hi".data(using: .utf16)!).encoding == .utf8)
    }

    /// Bytes that are not UTF-8 are read in the encoding that holds them without loss, and written
    /// back byte for byte: a Latin-1 note is not rewritten with U+FFFD on its first save.
    @Test func readsLegacyEncodingsWithoutLoss() {
        let latin1 = Data([0x23, 0x20, 0x43, 0x61, 0x66, 0xE9, 0x20, 0x6E, 0x61, 0xEF, 0x76, 0x65, 0x0A])
        let decoded = MarkdownText.read(latin1)
        #expect(decoded.text == "# Café naïve\n")
        #expect(decoded.isLossy == false)
        #expect(decoded.text.data(using: decoded.encoding) == latin1)
        #expect(MarkdownText.decode(latin1) == "# Café naïve\n")

        let shiftJIS = Data([0x23, 0x20, 0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA, 0x0A])
        let japanese = MarkdownText.read(shiftJIS)
        #expect(japanese.isLossy == false)
        #expect(japanese.text.data(using: japanese.encoding) == shiftJIS)
    }

    /// A re-read of a file the app wrote in a legacy encoding decodes it the same way.
    @Test func prefersTheEncodingItWasReadWith() {
        let macRoman = "# Café\n".data(using: .macOSRoman)!
        let decoded = MarkdownText.read(macRoman, preferring: .macOSRoman)
        #expect(decoded.text == "# Café\n")
        #expect(decoded.encoding == .macOSRoman)
        #expect(MarkdownText.read(Data("# Hi".utf8), preferring: .macOSRoman).encoding == .utf8)
    }
}
