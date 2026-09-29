import JavaScriptCore
import Testing
@testable import Uncial

@Suite struct PreviewScriptsTests {
    /// Runs the find bar's count script on a page whose text is `text`.
    private func count(_ query: String, in text: String) -> Int32 {
        let context = JSContext()!
        context.setObject(["body": ["innerText": text]], forKeyedSubscript: "document" as NSString)
        return context.evaluateScript(PreviewScripts.countMatches(query)).toInt32()
    }

    /// The query goes into the script as a string literal: quotes and backslashes are text to find.
    @Test func countTakesTheQueryLiterally() {
        #expect(count("it's \"quoted\"", in: "it's \"quoted\" and it's \"quoted\"") == 2)
        #expect(count("a\\b", in: "a\\b a\\b") == 2)
    }

    /// The count agrees with what WebKit's find selects, which ignores case and diacritics and folds ß:
    /// "resume" used to count 1 of the 4 matches WebKit selected, and "strasse" none.
    @Test func countFoldsTextLikeWebKitsFind() {
        #expect(count("resume", in: "Résumé resume RESUMÉ résume") == 4)
        #expect(count("Résumé", in: "Résumé resume") == 2)
        #expect(count("strasse", in: "Straße STRASSE") == 2)
        #expect(count("ß", in: "Straße strasse") == 2)
        #expect(count("", in: "x") == 0)
    }
}
