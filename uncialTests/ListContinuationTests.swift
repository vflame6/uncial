import Foundation
import Testing
@testable import Uncial

@Suite struct ListContinuationTests {
    /// Applies the Return edit to `text` (caret at `caret`, default end) and marks the caret with `|`.
    private func pressReturn(in text: String, at caret: Int? = nil) -> String? {
        let source = text as NSString
        guard let edit = ListContinuation.edit(in: source, at: caret ?? source.length) else { return nil }
        let result = source.replacingCharacters(in: edit.range, with: edit.replacement) as NSString
        return result.replacingCharacters(in: edit.selection, with: "|")
    }

    @Test func continuesBullets() {
        #expect(pressReturn(in: "- item") == "- item\n- |")
        #expect(pressReturn(in: "* a") == "* a\n* |")
        #expect(pressReturn(in: "+ a") == "+ a\n+ |")
    }

    @Test func incrementsOrderedItems() {
        #expect(pressReturn(in: "1. a") == "1. a\n2. |")
        #expect(pressReturn(in: "9) a") == "9) a\n10) |")
    }

    @Test func resetsTaskBoxes() {
        #expect(pressReturn(in: "- [x] done") == "- [x] done\n- [ ] |")
        #expect(pressReturn(in: "- [ ] todo") == "- [ ] todo\n- [ ] |")
    }

    @Test func keepsIndentationAndSpacing() {
        #expect(pressReturn(in: "  -   a") == "  -   a\n  -   |")
        #expect(pressReturn(in: "\t- a") == "\t- a\n\t- |")
    }

    @Test func continuesQuotesAndQuotedLists() {
        #expect(pressReturn(in: "> quote") == "> quote\n> |")
        #expect(pressReturn(in: "> > deep") == "> > deep\n> > |")
        #expect(pressReturn(in: "> - item") == "> - item\n> - |")
    }

    @Test func emptyItemsEndTheList() {
        #expect(pressReturn(in: "- a\n- ") == "- a\n|")
        #expect(pressReturn(in: "1. ") == "|")
        #expect(pressReturn(in: "> - ") == "> |")
        #expect(pressReturn(in: "> ") == "|")
        #expect(pressReturn(in: "- [ ] ") == "|")
    }

    @Test func splitsTextAfterTheCaretAndWorksOnAnyLine() {
        #expect(pressReturn(in: "- ab", at: 3) == "- a\n- |b")
        #expect(pressReturn(in: "- a\ntext", at: 3) == "- a\n- |\ntext")
    }

    @Test func leavesOtherLinesAlone() {
        #expect(pressReturn(in: "plain") == nil)
        #expect(pressReturn(in: "-item") == nil)
        #expect(pressReturn(in: "- item", at: 1) == nil)
        #expect(pressReturn(in: "1.5 things") == nil)
    }
}
