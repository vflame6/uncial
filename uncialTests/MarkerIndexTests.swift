import Foundation
import Testing
@testable import Uncial

@Suite struct MarkerIndexTests {
    private func index(_ text: String) -> MarkerIndex {
        MarkerIndex(tokens: MarkdownHighlighter.tokens(in: text))
    }

    /// The glyph delegate asks `hasHidden(in:)` and `hasBullet(in:)` for every glyph run: they answer by
    /// binary search, exactly as a scan would (a scan over thousands of markers cost 50–90 ms per keystroke).
    @Test func rangeQueriesAreExactAndFast() {
        let text = String(repeating: "- a *b* c\n", count: 5000)
        let markers = MarkerIndex(tokens: MarkdownHighlighter.tokens(in: text))
        var mismatches: [NSRange] = []
        for location in 0..<200 {
            for length in [0, 1, 3, 10] {
                let range = NSRange(location: location, length: length)
                let hidden = markers.hidden.contains { NSIntersectionRange($0, range).length > 0 }
                let bullet = markers.bullets.contains { NSLocationInRange($0, range) }
                if markers.hasHidden(in: range) != hidden || markers.hasBullet(in: range) != bullet { mismatches.append(range) }
            }
        }
        #expect(mismatches.isEmpty)
        let length = (text as NSString).length
        let elapsed = ContinuousClock().measure {
            for location in stride(from: 0, to: length, by: 4) {
                _ = markers.hasHidden(in: NSRange(location: location, length: 4))
                _ = markers.hasBullet(in: NSRange(location: location, length: 4))
            }
        }
        #expect(elapsed < .milliseconds(100), "took \(elapsed)")
    }

    @Test func hidesMarkersButNotImages() {
        let text = "## H **b**\n![a](i.png)"
        let markers = index(text)
        #expect(markers.hidden == [NSRange(location: 0, length: 3), NSRange(location: 5, length: 2), NSRange(location: 8, length: 2)])
        #expect(markers.isHidden(0) && markers.isHidden(2) && !markers.isHidden(3) && markers.isHidden(9) && !markers.isHidden(11))
        #expect(markers.hasHidden(in: NSRange(location: 4, length: 2)) && !markers.hasHidden(in: NSRange(location: 11, length: 12)))
        let resolved = MarkerIndex(tokens: MarkdownHighlighter.tokens(in: text), resolvedImages: [11])
        #expect(resolved.hidden.count == 5 && resolved.isHidden(11) && resolved.isHidden(16) && !resolved.isHidden(13))
    }

    @Test func hidesResolvedDiagramBlocksButTheirLastNewline() {
        // "intro\n" 0–5, "```mermaid" 6–15, "pie" 17–19, "```" 21–23, "\n" 24, "after" 25–29.
        let text = "intro\n```mermaid\npie\n```\nafter"
        let tokens = MarkdownHighlighter.tokens(in: text)
        let block = NSRange(location: 6, length: 18)
        let plain = MarkerIndex(tokens: tokens, pictureBlocks: [block])
        #expect(plain.pictureRanges == [block] && !plain.isHidden(17) && plain.isHidden(6) && plain.hasPicture(touching: NSRange(location: 20, length: 0)))
        let resolved = MarkerIndex(tokens: tokens, pictureBlocks: [block], resolvedDiagrams: [6])
        #expect(resolved.pictureRanges == [block])
        #expect(resolved.hidden == [NSRange(location: 6, length: 18)])
        #expect(resolved.isHidden(6) && resolved.isHidden(17) && resolved.isHidden(23) && !resolved.isHidden(24) && !resolved.isHidden(25))
        #expect(resolved.hasPicture(touching: NSRange(location: 17, length: 0)) && !resolved.hasPicture(touching: NSRange(location: 25, length: 3)))
        #expect(resolved.revealedRange(for: NSRange(location: 24, length: 0), in: text as NSString) == NSRange(location: 6, length: 19))
        #expect(MarkerIndex.merged([NSRange(location: 5, length: 2), NSRange(location: 0, length: 3), NSRange(location: 6, length: 4)]) == [NSRange(location: 0, length: 3), NSRange(location: 5, length: 5)])
    }

    @Test func hidesPicturedMathButItsAnchor() {
        // "a $x$ b\n" 0–7 (token 2–4), "$$\n" 8–10, "y\n" 11–12, "$$\n" 13–15, "z" 16.
        let text = "a $x$ b\n$$\ny\n$$\nz"
        let tokens = MarkdownHighlighter.tokens(in: text)
        let block = NSRange(location: 8, length: 7)
        let plain = MarkerIndex(tokens: tokens, pictureBlocks: [block])
        #expect(plain.hidden == [NSRange(location: 2, length: 1), NSRange(location: 4, length: 1), NSRange(location: 8, length: 2), NSRange(location: 13, length: 2)])
        #expect(plain.blocks == [block] && plain.anchors.isEmpty && !plain.isAnchor(2))
        #expect(plain.hasPicture(touching: NSRange(location: 3, length: 0)) && plain.hasPicture(touching: NSRange(location: 11, length: 0)) && !plain.hasPicture(touching: NSRange(location: 16, length: 0)))
        #expect(plain.revealedRange(for: NSRange(location: 11, length: 0), in: text as NSString) == NSRange(location: 8, length: 8))
        let resolved = MarkerIndex(tokens: tokens, pictureBlocks: [block], resolvedMath: [2: 2, 8: 13])
        #expect(resolved.anchors == [2, 13] && resolved.isAnchor(13) && !resolved.isAnchor(3))
        #expect(resolved.hasAnchor(in: NSRange(location: 0, length: 3)) && !resolved.hasAnchor(in: NSRange(location: 3, length: 10)))
        #expect(resolved.hidden == [NSRange(location: 3, length: 2), NSRange(location: 8, length: 5), NSRange(location: 14, length: 1)])
        #expect(!resolved.isHidden(2) && resolved.isHidden(3) && resolved.isHidden(4) && !resolved.isHidden(5) && !resolved.isHidden(13) && resolved.isHidden(14) && !resolved.isHidden(15))
    }

    @Test func collectsBulletsAndBlocks() {
        let text = "- a\n1. b\n```\nx\n```\ntext\n~~~\nopen"
        let markers = index(text)
        #expect(markers.bullets == [0])
        #expect(markers.blocks == [NSRange(location: 9, length: 9), NSRange(location: 24, length: 8)])
    }

    @Test func revealsTheCaretLineOrTheWholeBlock() {
        let text = "# H\n```\nx\n```\nend" as NSString
        let markers = index(text as String)
        #expect(markers.revealedRange(for: NSRange(location: 1, length: 0), in: text) == NSRange(location: 0, length: 4))
        #expect(markers.revealedRange(for: NSRange(location: 8, length: 0), in: text) == NSRange(location: 4, length: 10))
        #expect(markers.revealedRange(for: NSRange(location: 5, length: 0), in: text) == NSRange(location: 4, length: 10))
        #expect(markers.revealedRange(for: NSRange(location: 1, length: 8), in: text) == NSRange(location: 0, length: 14))
        #expect(markers.revealedRange(for: NSRange(location: 17, length: 0), in: text) == NSRange(location: 14, length: 3))
        #expect(MarkerIndex.empty.revealedRange(for: NSRange(location: 0, length: 0), in: "") == NSRange(location: 0, length: 0))
    }

    /// Ranges taken from a longer text (the storage mid-edit, or the text before a reload) never
    /// reach past the text they are applied to.
    @Test func revealsWithinTheTextWhenBlocksAreStale() {
        let stale = index("intro\n```swift\nlet x")
        let text = "intro\n```swift\nlet " as NSString
        #expect(stale.revealedRange(for: NSRange(location: 19, length: 0), in: text) == NSRange(location: 6, length: 13))
        #expect(stale.revealedRange(for: NSRange(location: 25, length: 3), in: text) == NSRange(location: 6, length: 13))
        #expect(stale.revealedRange(for: NSRange(location: 0, length: 0), in: "") == NSRange(location: 0, length: 0))
    }
}
