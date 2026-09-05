import Testing
@testable import UncialCore

@Suite struct HTMLEscapingTests {
    @Test func escapesMarkup() {
        #expect(HTMLEscaping.escape("a < b & \"c\" > d") == "a &lt; b &amp; &quot;c&quot; &gt; d")
    }

    @Test func unescapesNamedAndNumericEntities() {
        #expect(HTMLEscaping.unescape("C &amp; D &lt;x&gt; &quot;q&quot; &#39;s&#39; &#x41;") == "C & D <x> \"q\" 's' A")
    }

    @Test func leavesUnknownEntitiesAlone() {
        #expect(HTMLEscaping.unescape("&bogus; & plain") == "&bogus; & plain")
    }
}
