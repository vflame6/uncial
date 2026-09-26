import Foundation
import Testing
@testable import UncialCore

@Suite struct MarkdownTextTests {
    @Test func decodesUTF8AndStripsBOM() {
        #expect(MarkdownText.decode(Data([0xEF, 0xBB, 0xBF] + Array("# Hi".utf8))) == "# Hi")
        #expect(MarkdownText.decode(Data("# Hi".utf8)) == "# Hi")
    }

    private func file(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uncial-prefix-\(UUID().uuidString).md")
        try data.write(to: url)
        return url
    }

    /// A view that shows only the beginning (a Finder thumbnail) reads only that much: a longer file is
    /// cut at its last line break inside the limit, and a cut never splits a character.
    @Test func readsAPrefixWithoutSplittingCharacters() throws {
        let small = try file(Data("# Hi\n".utf8))
        defer { try? FileManager.default.removeItem(at: small) }
        #expect(try MarkdownText.readPrefix(of: small, maxBytes: 64) == "# Hi\n")

        let lines = (0..<100).map { "line \($0)" }.joined(separator: "\n")
        let long = try file(Data(lines.utf8))
        defer { try? FileManager.default.removeItem(at: long) }
        let prefix = try MarkdownText.readPrefix(of: long, maxBytes: 100)
        #expect(prefix.hasSuffix("\n") && lines.hasPrefix(prefix) && prefix.utf8.count <= 100)

        let accents = String(repeating: "é", count: 200)
        let oneLine = try file(Data(accents.utf8))
        defer { try? FileManager.default.removeItem(at: oneLine) }
        let cut = try MarkdownText.readPrefix(of: oneLine, maxBytes: 101)
        #expect(!cut.isEmpty && accents.hasPrefix(cut))

        let faces = String(repeating: "😀", count: 100)
        let utf16 = try file(faces.data(using: .utf16LittleEndian).map { Data([0xFF, 0xFE]) + $0 }!)
        defer { try? FileManager.default.removeItem(at: utf16) }
        let half = try MarkdownText.readPrefix(of: utf16, maxBytes: 100)
        #expect(!half.isEmpty && faces.hasPrefix(half))
    }

    /// A 10 MB fenced block outlines in no time from a prefix; parsing it whole took 1.9 s and 300 MB.
    @Test func aPrefixOutlinesAHugeFileQuickly() throws {
        let huge = try file(Data(("```\n" + String(repeating: "0123456789abcdef\n", count: 640_000) + "```\n").utf8))
        defer { try? FileManager.default.removeItem(at: huge) }
        var count = 0
        let elapsed = ContinuousClock().measure {
            count = (try? MarkdownOutline.blocks(in: MarkdownText.readPrefix(of: huge, maxBytes: 64 << 10), limit: 80).count) ?? 0
        }
        #expect(count == 1)
        #expect(elapsed < .milliseconds(200), "took \(elapsed)")
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
