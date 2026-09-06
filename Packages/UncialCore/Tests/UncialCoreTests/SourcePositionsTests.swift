import Testing
@testable import UncialCore

@Suite struct SourcePositionsTests {
    @Test func shiftsEveryLineNumber() {
        let html = "<h1 data-sourcepos=\"1:1-1:5\">T</h1>\n<ul data-sourcepos=\"3:1-4:3\"><li data-sourcepos=\"3:1-3:3\">a</li></ul>"
        let shifted = SourcePositions.shift(html, by: 4)
        #expect(shifted.contains("data-sourcepos=\"5:1-5:5\""))
        #expect(shifted.contains("data-sourcepos=\"7:1-8:3\""))
        #expect(shifted.contains("data-sourcepos=\"7:1-7:3\""))
    }

    @Test func zeroOffsetAndNoAttributesAreIdentity() {
        #expect(SourcePositions.shift("<p>x</p>", by: 3) == "<p>x</p>")
        #expect(SourcePositions.shift("<p data-sourcepos=\"1:1-1:1\">x</p>", by: 0) == "<p data-sourcepos=\"1:1-1:1\">x</p>")
    }
}
