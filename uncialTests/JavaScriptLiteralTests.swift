import Testing
@testable import Uncial

@Suite struct JavaScriptLiteralTests {
    @Test func escapesQuotesBackslashesAndNewlines() {
        #expect(JavaScriptLiteral.string("a\"b\\c\nd\re") == "\"a\\\"b\\\\c\\nd\\re\"")
    }

    @Test func escapesLineSeparatorsAndControlCharacters() {
        #expect(JavaScriptLiteral.string("x\u{2028}y\u{2029}\u{01}") == "\"x\\u2028y\\u2029\\u0001\"")
    }

    @Test func keepsUnicodeAndMarkup() {
        #expect(JavaScriptLiteral.string("<p>héllo</p>") == "\"<p>héllo</p>\"")
    }
}
