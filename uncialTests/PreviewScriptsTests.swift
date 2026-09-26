import JavaScriptCore
import Testing
@testable import Uncial

@Suite struct PreviewScriptsTests {
    @Test func countScriptEmbedsTheQueryAsALiteral() {
        let script = PreviewScripts.countMatches("it's \"quoted\"")
        #expect(script.contains("\"it's \\\"quoted\\\"\""))
        #expect(script.contains("innerText"))
    }

    /// The count agrees with what WebKit's find selects, which ignores case and diacritics and folds ß:
    /// "resume" used to count 1 of the 4 matches WebKit selected, and "strasse" none.
    @Test func countFoldsTextLikeWebKitsFind() {
        func count(_ query: String, in text: String) -> Int32 {
            let context = JSContext()!
            context.setObject(["body": ["innerText": text]], forKeyedSubscript: "document" as NSString)
            return context.evaluateScript(PreviewScripts.countMatches(query)).toInt32()
        }
        #expect(count("resume", in: "Résumé resume RESUMÉ résume") == 4)
        #expect(count("Résumé", in: "Résumé resume") == 2)
        #expect(count("strasse", in: "Straße STRASSE") == 2)
        #expect(count("ß", in: "Straße strasse") == 2)
        #expect(count("", in: "x") == 0)
    }
}
