import Foundation
import Testing
import UncialCore
@testable import Uncial

/// Live Preview against the page on the GFM spec's examples: an example is flagged when the page shows
/// text that Live Preview hides (its visible text, the source without the markers it hides, lacks the
/// page's text as a subsequence; whitespace ignored). The spec comes from the swift-cmark checkout of
/// `make test`'s build; examples with entities (`&`) or math (`$`, which the page reads on its own) are
/// left out. `knownDifferences` may only shrink.
@MainActor
@Suite struct SpecDifferentialTests {
    static let spec = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/SourcePackages/checkouts/swift-cmark/test/spec.txt")

    /// Examples where Live Preview still hides text the page shows (2026-09-26; the audit found 71).
    static let knownDifferences: Set<Int> = [
        63
    ]

    struct Example {
        let number: Int
        let markdown: String
    }

    static func examples() throws -> [Example] {
        let lines = try String(contentsOf: spec, encoding: .utf8).components(separatedBy: "\n")
        let fence = String(repeating: "`", count: 32)
        var examples: [Example] = []
        var index = 0
        while index < lines.count {
            if lines[index].hasPrefix(fence + " example") {
                var markdown: [String] = []
                index += 1
                while index < lines.count, lines[index] != "." {
                    markdown.append(lines[index])
                    index += 1
                }
                while index < lines.count, !lines[index].hasPrefix(fence) { index += 1 }
                examples.append(Example(number: examples.count + 1, markdown: markdown.joined(separator: "\n").replacingOccurrences(of: "→", with: "\t") + "\n"))
            }
            index += 1
        }
        return examples
    }

    /// What the page shows: the rendered HTML without tags, a few entities read back.
    static func pageText(_ markdown: String) -> String {
        MarkdownRenderer().renderBody(markdown)
            .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// What Live Preview shows: the source without the markers it hides.
    static func livePreviewText(_ markdown: String) -> String {
        let markers = MarkerIndex(tokens: MarkdownHighlighter.tokens(in: markdown))
        let units = Array(markdown.utf16)
        let visible = units.indices.filter { !markers.isHidden($0) }.map { units[$0] }
        return String(decoding: visible, as: UTF16.self)
    }

    static func isSubsequence(_ needle: [Character], of haystack: [Character]) -> Bool {
        var index = 0
        for character in haystack where index < needle.count && character == needle[index] { index += 1 }
        return index == needle.count
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: SpecDifferentialTests.spec.path), "needs the swift-cmark checkout of make test's build"))
    func livePreviewShowsWhatThePageShows() throws {
        var flagged: Set<Int> = []
        for example in try Self.examples() where !example.markdown.contains("&") && !example.markdown.contains("$") {
            let page = Self.pageText(example.markdown).filter { !$0.isWhitespace }
            let preview = Self.livePreviewText(example.markdown).filter { !$0.isWhitespace }
            if !Self.isSubsequence(Array(page), of: Array(preview)) { flagged.insert(example.number) }
        }
        let new = flagged.subtracting(Self.knownDifferences).sorted()
        let fixed = Self.knownDifferences.subtracting(flagged).sorted()
        #expect(new.isEmpty, "Live Preview now hides text the page shows in examples \(new)")
        #expect(fixed.isEmpty, "examples \(fixed) agree now: take them off knownDifferences")
    }
}
