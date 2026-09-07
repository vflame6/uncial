import Testing
@testable import Uncial

@Suite struct PreviewScriptsTests {
    @Test func countScriptEmbedsTheQueryAsALiteral() {
        let script = PreviewScripts.countMatches("it's \"quoted\"")
        #expect(script.contains("\"it's \\\"quoted\\\"\""))
        #expect(script.contains("innerText"))
    }
}
