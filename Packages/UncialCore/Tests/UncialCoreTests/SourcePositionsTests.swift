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

    @Test func annotateLabelsEachNewSourceLineOnce() {
        let html = "<ul data-sourcepos=\"3:1-4:5\">\n<li data-sourcepos=\"3:1-3:5\"><p data-sourcepos=\"3:3-3:5\">a</p></li>\n<li data-sourcepos=\"4:1-4:5\">b</li>\n</ul>"
        let out = SourcePositions.annotate(html)
        #expect(out.contains("<ul data-line=\"3\" data-sourcepos=\"3:1-4:5\">"))
        #expect(out.contains("<li data-sourcepos=\"3:1-3:5\"><p data-sourcepos=\"3:3-3:5\">"))
        #expect(out.contains("<li data-line=\"4\" data-sourcepos=\"4:1-4:5\">"))
    }

    @Test func annotateSkipsTableRowsAndCells() {
        let html = "<table data-sourcepos=\"1:1-3:5\">\n<tr data-sourcepos=\"1:1-1:5\"><th data-sourcepos=\"1:2-1:2\">a</th></tr>\n<tr data-sourcepos=\"3:1-3:5\"><td data-sourcepos=\"3:2-3:2\">1</td></tr></table>"
        let out = SourcePositions.annotate(html)
        #expect(out.contains("<table data-line=\"1\""))
        #expect(!out.contains("<tr data-line"))
        #expect(!out.contains("<th data-line"))
        #expect(!out.contains("<td data-line"))
    }

    @Test func annotateNumbersFencedCodeLinesAfterTheFence() {
        let html = "<pre data-sourcepos=\"5:1-8:3\"><code class=\"language-swift\">let a = 1\nlet b = 2\n</code></pre>"
        #expect(SourcePositions.annotate(html) == "<pre data-sourcepos=\"5:1-8:3\"><code class=\"language-swift\"><span class=\"line\" data-line=\"6\">let a = 1</span>\n<span class=\"line\" data-line=\"7\">let b = 2</span>\n</code></pre>")
    }

    @Test func annotateNumbersIndentedCodeFromItsFirstLine() {
        let out = SourcePositions.annotate("<pre data-sourcepos=\"6:5-8:0\"><code>indented\ntwo\n</code></pre>")
        #expect(out.contains("<span class=\"line\" data-line=\"6\">indented</span>"))
        #expect(out.contains("<span class=\"line\" data-line=\"7\">two</span>"))
        #expect(!out.contains("<pre data-line"))
    }

    @Test func annotateHandlesAttributesBeforeThePositionAndPlainHTML() {
        #expect(SourcePositions.annotate("<h1 id=\"t\" data-sourcepos=\"1:1-1:3\">T</h1>") == "<h1 id=\"t\" data-line=\"1\" data-sourcepos=\"1:1-1:3\">T</h1>")
        #expect(SourcePositions.annotate("<p>x</p>") == "<p>x</p>")
    }
}
