import Foundation
import Testing
@testable import Uncial

@Suite struct MarkerIndexTests {
    private func index(_ text: String) -> MarkerIndex {
        MarkerIndex(tokens: MarkdownHighlighter.tokens(in: text))
    }

    @Test func hidesMarkersButNotImages() {
        let text = "## H **b**\n![a](i.png)"
        let markers = index(text)
        #expect(markers.hidden == [NSRange(location: 0, length: 3), NSRange(location: 5, length: 2), NSRange(location: 8, length: 2)])
        #expect(markers.isHidden(0) && markers.isHidden(2) && !markers.isHidden(3) && markers.isHidden(9) && !markers.isHidden(11))
        #expect(markers.hasHidden(in: NSRange(location: 4, length: 2)) && !markers.hasHidden(in: NSRange(location: 11, length: 12)))
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
}
