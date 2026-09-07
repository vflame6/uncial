import Foundation
import Testing
@testable import Uncial

@Suite struct AutoPairingTests {
    /// Feeds `keys` to the model one at a time the way the text view would ("\n" is Return, "\u{8}" is
    /// Backspace, anything else a typed character): edits are applied, ordinary keys are mapped through
    /// `textChanged`, and every keystroke ends with `selectionChanged`. Returns the text with `|` at the
    /// caret or `[…]` around the selection.
    private func type(_ keys: String, into text: String = "", selection: NSRange? = nil) -> String {
        var pairing = AutoPairing()
        var current = text as NSString
        var range = selection ?? NSRange(location: current.length, length: 0)
        for key in keys {
            let typed = String(key)
            let edit: AutoPairing.Edit?
            switch key {
            case "\n": edit = pairing.newline(in: current, selection: range)
            case "\u{8}": edit = pairing.deleteBackward(in: current, selection: range)
            default: edit = pairing.typed(typed, in: current, selection: range)
            }
            if let edit {
                current = current.replacingCharacters(in: edit.range, with: edit.replacement) as NSString
                range = edit.selection
            } else if key == "\u{8}" {
                let deleted = range.length > 0 ? range : NSRange(location: max(range.location - 1, 0), length: min(range.location, 1))
                current = current.replacingCharacters(in: deleted, with: "") as NSString
                pairing.textChanged(in: deleted, replacementLength: 0)
                range = NSRange(location: deleted.location, length: 0)
            } else {
                current = current.replacingCharacters(in: range, with: typed) as NSString
                pairing.textChanged(in: range, replacementLength: typed.utf16.count)
                range = NSRange(location: range.location + typed.utf16.count, length: 0)
            }
            pairing.selectionChanged(to: range)
        }
        let marker = range.length == 0 ? "|" : "[\(current.substring(with: range))]"
        return current.replacingCharacters(in: range, with: marker)
    }

    @Test func closesBracketsAndSkipsTheirClosers() {
        #expect(type("(") == "(|)")
        #expect(type("([])") == "([])|")
        #expect(type("{a}") == "{a}|")
        #expect(type("[text](url)") == "[text](url)|")
    }

    @Test func closesOnlyInFrontOfWhitespacePunctuationOrClosers() {
        #expect(type("[", into: "abc", selection: NSRange(location: 1, length: 0)) == "a[|bc")
        #expect(type("(", into: "x.", selection: NSRange(location: 1, length: 0)) == "x(|).")
        #expect(type("[", into: "()", selection: NSRange(location: 1, length: 0)) == "([|])")
        #expect(type("(", into: "a b", selection: NSRange(location: 1, length: 0)) == "a(|) b")
    }

    @Test func untrackedClosersAreNotSkipped() {
        #expect(type(")", into: "()", selection: NSRange(location: 1, length: 0)) == "()|)")
    }

    @Test func pairsMarkersOnlyAtWordBoundaries() {
        #expect(type("*") == "*|*")
        #expect(type("_", into: "snake") == "snake_|")
        #expect(type("*", into: "2") == "2*|")
        #expect(type("*", into: "word", selection: NSRange(location: 0, length: 0)) == "*|word")
        #expect(type("*", into: "x *") == "x **|")
        #expect(type("*", into: "*em*", selection: NSRange(location: 0, length: 0)) == "*|*em*")
    }

    @Test func growsMarkerRunsAndSkipsOutOfThem() {
        #expect(type("**bold**") == "**bold**|")
        #expect(type("***") == "***|***")
        #expect(type("****") == "****|***")
        #expect(type("``") == "``|``")
        #expect(type("`code`") == "`code`|")
        #expect(type("(*a*)") == "(*a*)|")
    }

    @Test func quotesSkipButNeverGrow() {
        #expect(type("\"\"") == "\"\"|")
        #expect(type("\"hi\"") == "\"hi\"|")
        #expect(type("\"", into: "5") == "5\"|")
    }

    @Test func backspaceRemovesEmptyPairsOneLayerAtATime() {
        #expect(type("(\u{8}") == "|")
        #expect(type("**\u{8}") == "*|*")
        #expect(type("**\u{8}\u{8}") == "|")
        #expect(type("(a\u{8})") == "()|")
        #expect(type("\u{8}", into: "()", selection: NSRange(location: 1, length: 0)) == "|)")
    }

    @Test func whitespaceAfterAnEmptyEmphasisPairDropsTheCloser() {
        #expect(type("* item") == "* item|")
        #expect(type("***\n") == "***\n|")
        #expect(type("_ ") == "_ |")
        #expect(type("` ") == "` |`")
        #expect(type("(a b)") == "(a b)|")
    }

    @Test func returnInsideTripleBackticksMakesAFence() {
        #expect(type("```\n") == "```\n|\n```")
        #expect(type("```swift\n") == "```swift\n|\n```")
        #expect(type("```\n", into: "  ") == "  ```\n|\n```")
        #expect(type("```\n", into: "    ") == "    ```\n|```")
        #expect(type("```\n", into: "text ") == "text ```\n|```")
    }

    @Test func wrapsTheSelectionAndKeepsItSelected() {
        #expect(type("*", into: "bold", selection: NSRange(location: 0, length: 4)) == "*[bold]*")
        #expect(type("**", into: "bold", selection: NSRange(location: 0, length: 4)) == "**[bold]**")
        #expect(type("<", into: "url", selection: NSRange(location: 0, length: 3)) == "<[url]>")
        #expect(type("~", into: "old", selection: NSRange(location: 0, length: 3)) == "~[old]~")
        #expect(type("'", into: "q", selection: NSRange(location: 0, length: 1)) == "'[q]'")
        #expect(type("x", into: "bold", selection: NSRange(location: 0, length: 4)) == "x|")
    }

    @Test func externalEditsMoveTrackedPairs() {
        var pairing = AutoPairing()
        _ = pairing.typed("(", in: "", selection: NSRange(location: 0, length: 0))
        let pair = AutoPairing.Pair("(", ")")
        #expect(pairing.tracked == [AutoPairing.Tracked(pair: pair, open: NSRange(location: 0, length: 1), close: NSRange(location: 1, length: 1))])
        pairing.textChanged(in: NSRange(location: 0, length: 0), replacementLength: 3)
        #expect(pairing.tracked == [AutoPairing.Tracked(pair: pair, open: NSRange(location: 3, length: 1), close: NSRange(location: 4, length: 1))])
        pairing.textChanged(in: NSRange(location: 4, length: 0), replacementLength: 2)
        #expect(pairing.tracked.first?.close == NSRange(location: 6, length: 1))
        pairing.textChanged(in: NSRange(location: 7, length: 0), replacementLength: 5)
        #expect(pairing.tracked.first?.close == NSRange(location: 6, length: 1))
        pairing.textChanged(in: NSRange(location: 3, length: 2), replacementLength: 0)
        #expect(pairing.tracked.isEmpty)
    }

    @Test func leavingThePairForgetsIt() {
        var pairing = AutoPairing()
        _ = pairing.typed("(", in: "", selection: NSRange(location: 0, length: 0))
        pairing.selectionChanged(to: NSRange(location: 1, length: 0))
        #expect(pairing.tracked.count == 1)
        pairing.selectionChanged(to: NSRange(location: 2, length: 0))
        #expect(pairing.tracked.isEmpty)
        _ = pairing.typed("(", in: "", selection: NSRange(location: 0, length: 0))
        pairing.selectionChanged(to: NSRange(location: 0, length: 0))
        #expect(pairing.tracked.isEmpty)
    }

    @Test func staleEntriesAreIgnored() {
        var pairing = AutoPairing()
        _ = pairing.typed("(", in: "", selection: NSRange(location: 0, length: 0))
        #expect(pairing.typed(")", in: "x)", selection: NSRange(location: 1, length: 0)) == nil)
        #expect(pairing.tracked.isEmpty)
    }

    @Test func ignoresMultiCharacterInput() {
        var pairing = AutoPairing()
        #expect(pairing.typed("()", in: "", selection: NSRange(location: 0, length: 0)) == nil)
        #expect(pairing.typed("", in: "", selection: NSRange(location: 0, length: 0)) == nil)
        #expect(pairing.tracked.isEmpty)
    }

    @Test func tildesPairOnlyAtLineStart() {
        #expect(type("~", into: "about ") == "about ~|")
        #expect(type("~~gone~~") == "~~gone~~|")
        #expect(type("~~~\n") == "~~~\n|\n~~~")
        #expect(type("~ ") == "~ |")
        #expect(type("~", into: "x\n") == "x\n~|~")
    }
}
