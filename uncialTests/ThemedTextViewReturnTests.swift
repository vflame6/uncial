import AppKit
import Testing
@testable import Uncial

/// What Return does in the editor, through `insertNewline`.
@MainActor
@Suite struct ThemedTextViewReturnTests {
    /// The text after Return with the caret right after `prefix`.
    private func pressingReturn(in text: String, after prefix: String) -> String {
        let view = editor(text, caret: (prefix as NSString).length, tracksWidth: true)
        view.insertNewline(nil)
        return view.string
    }

    @Test func continuesListsOutsideCode() {
        #expect(pressingReturn(in: "- one\n", after: "- one") == "- one\n- \n")
    }

    /// Code, math and front matter are literal: Return is a line break there, never a list or quote
    /// continuation that removes a marker-only line or adds a prefix.
    @Test func isAPlainLineBreakInLiteralBlocks() {
        #expect(pressingReturn(in: "```yaml\nitems:\n  - \n```\n", after: "```yaml\nitems:\n  - ") == "```yaml\nitems:\n  - \n\n```\n")
        #expect(pressingReturn(in: "```diff\n+ added\n```\n", after: "```diff\n+ added") == "```diff\n+ added\n\n```\n")
        #expect(pressingReturn(in: "~~~\n> \n~~~\n", after: "~~~\n> ") == "~~~\n> \n\n~~~\n")
        #expect(pressingReturn(in: "$$\n- \n$$\n", after: "$$\n- ") == "$$\n- \n\n$$\n")
        #expect(pressingReturn(in: "---\ntags:\n  - one\n---\n", after: "---\ntags:\n  - one") == "---\ntags:\n  - one\n\n---\n")
    }
}
