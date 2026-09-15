import Foundation
import Testing
@testable import Uncial

@Suite struct DocumentStatisticsTests {
    private let english = Locale(identifier: "en_US")

    @Test func emptyDocumentHasOneLine() {
        #expect(DocumentStatistics(text: "") == DocumentStatistics(lines: 1, words: 0, characters: 0))
    }

    @Test func countsPlainText() {
        #expect(DocumentStatistics(text: "Hello world") == DocumentStatistics(lines: 1, words: 2, characters: 11))
    }

    @Test func linesAreCountedLikeTheGutter() {
        #expect(DocumentStatistics(text: "a\nb").lines == 2)
        #expect(DocumentStatistics(text: "a\n").lines == 2)
        #expect(DocumentStatistics(text: "a\r\nb").lines == 2)
        #expect(DocumentStatistics(text: "a\rb").lines == 2)
        #expect(DocumentStatistics(text: "a\n\nb").lines == 3)
    }

    @Test func markdownMarkersAreNotWords() {
        let text = "# Title\n\n- item one\n- **bold** and *em*\n\n---\n\n> `code` [link](https://example.com/path)\n"
        #expect(DocumentStatistics(text: text).words == 11)
    }

    @Test func connectorsJoinWordsAndNumbers() {
        #expect(DocumentStatistics(text: "don't stop well-known 3,857 items e.g. v1.2 at 10:30").words == 9)
        #expect(DocumentStatistics(text: "snake_case _em_ 'quoted' well--split").words == 5)
    }

    @Test func cjkCharactersCountOneEach() {
        #expect(DocumentStatistics(text: "日本語のテキスト").words == 8)
        #expect(DocumentStatistics(text: "中文 test").words == 3)
        #expect(DocumentStatistics(text: "한국어").words == 3)
    }

    @Test func combiningMarksStayInsideWords() {
        let statistics = DocumentStatistics(text: "nai\u{308}ve")
        #expect(statistics.words == 1)
        #expect(statistics.characters == 5)
    }

    @Test func emojiAreCharactersNotWords() {
        let statistics = DocumentStatistics(text: "🔥 Hot Links ❤️")
        #expect(statistics.words == 2)
        #expect(statistics.characters == 13)
    }

    @Test func charactersIncludeWhitespaceAndLineBreaks() {
        #expect(DocumentStatistics(text: "a b\nc").characters == 5)
    }

    @Test func phrasesAgreeInNumber() {
        #expect(DocumentStatistics.phrase(1, "line", locale: english) == "1 line")
        #expect(DocumentStatistics.phrase(0, "word", locale: english) == "0 words")
        #expect(DocumentStatistics.phrase(3857, "character", locale: english) == "3,857 characters")
    }
}
