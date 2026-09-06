import Foundation
import Testing
@testable import Uncial

@Suite struct LineIndexTests {
    @Test func emptyTextHasOneEmptyLine() {
        let index = LineIndex(text: "")
        #expect(index.count == 1)
        #expect(index.line(at: 0) == 0)
        #expect(index.range(ofLine: 0) == NSRange(location: 0, length: 0))
    }

    @Test func splitsOnNewlinesIncludingTrailingOne() {
        let index = LineIndex(text: "a\nbb\n")
        #expect(index.count == 3)
        #expect(index.range(ofLine: 0) == NSRange(location: 0, length: 1))
        #expect(index.range(ofLine: 1) == NSRange(location: 2, length: 2))
        #expect(index.range(ofLine: 2) == NSRange(location: 5, length: 0))
        #expect(index.line(at: 0) == 0)
        #expect(index.line(at: 1) == 0)
        #expect(index.line(at: 2) == 1)
        #expect(index.line(at: 4) == 1)
        #expect(index.line(at: 5) == 2)
    }

    @Test func handlesCRLFAsOneBreak() {
        let index = LineIndex(text: "a\r\nb")
        #expect(index.count == 2)
        #expect(index.range(ofLine: 0) == NSRange(location: 0, length: 1))
        #expect(index.range(ofLine: 1) == NSRange(location: 3, length: 1))
    }

    @Test func clampsOutOfRangeInput() {
        let index = LineIndex(text: "a\nb")
        #expect(index.line(at: -5) == 0)
        #expect(index.line(at: 100) == 1)
        #expect(index.range(ofLine: 9) == NSRange(location: 2, length: 1))
        #expect(index.range(ofLine: -1) == NSRange(location: 0, length: 1))
    }
}
