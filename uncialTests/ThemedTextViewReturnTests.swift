import AppKit
import Testing
@testable import Uncial

/// What Return does in the editor, through `insertNewline`.
@MainActor
@Suite struct ThemedTextViewReturnTests {
    private func editor(_ text: String, caretAfter prefix: String) -> ThemedTextView {
        let editor = ThemedTextView.standalone()
        editor.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        editor.replaceText(with: text)
        editor.setSelectedRange(NSRange(location: (prefix as NSString).length, length: 0))
        return editor
    }

    @Test func continuesListsOutsideCode() {
        let view = editor("- one\n", caretAfter: "- one")
        view.insertNewline(nil)
        #expect(view.string == "- one\n- \n")
    }

    /// Code, math and front matter are literal: Return is a line break there, never a list or quote
    /// continuation that removes a marker-only line or adds a prefix.
    @Test func isAPlainLineBreakInLiteralBlocks() {
        let yaml = "```yaml\nitems:\n  - \n```\n"
        var view = editor(yaml, caretAfter: "```yaml\nitems:\n  - ")
        view.insertNewline(nil)
        #expect(view.string == "```yaml\nitems:\n  - \n\n```\n")

        let diff = "```diff\n+ added\n```\n"
        view = editor(diff, caretAfter: "```diff\n+ added")
        view.insertNewline(nil)
        #expect(view.string == "```diff\n+ added\n\n```\n")

        let console = "~~~\n> \n~~~\n"
        view = editor(console, caretAfter: "~~~\n> ")
        view.insertNewline(nil)
        #expect(view.string == "~~~\n> \n\n~~~\n")

        let frontMatter = "---\ntags:\n  - one\n---\n"
        view = editor(frontMatter, caretAfter: "---\ntags:\n  - one")
        view.insertNewline(nil)
        #expect(view.string == "---\ntags:\n  - one\n\n---\n")
    }
}
