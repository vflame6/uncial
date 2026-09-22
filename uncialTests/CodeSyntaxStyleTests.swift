import AppKit
import Testing
import UncialCore
@testable import Uncial

@MainActor
@Suite struct CodeSyntaxStyleTests {
    private let style = EditorStyle(theme: .github, isDark: false)

    private func storage(_ text: String, inline: Bool = false) -> NSTextStorage {
        let storage = NSTextStorage(string: text, attributes: style.baseAttributes)
        let tokens = MarkdownHighlighter.tokens(in: text)
        if inline {
            InlineStyle(style: style).apply(tokens, to: storage)
        } else {
            for span in MarkdownHighlighter.spans(from: tokens) {
                storage.addAttributes(style.attributes(for: span.kind), range: span.range)
            }
        }
        CodeSyntaxStyle.apply(tokens, to: storage, style: style)
        return storage
    }

    private func color(_ storage: NSTextStorage, _ index: Int) -> NSColor? {
        storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    // "```swift\n" 0–8, "let x = 1 // hi\n" 9–24, "```" 25–27.
    private let swift = "```swift\nlet x = 1 // hi\n```"

    @Test func colorsTokensOfAKnownLanguage() {
        let storage = storage(swift)
        #expect(color(storage, 9) == style.color(for: .keyword))
        #expect(color(storage, 13) == style.foreground)
        #expect(color(storage, 17) == style.color(for: .number))
        #expect(color(storage, 19) == style.color(for: .comment))
        #expect(color(storage, 0) == style.code && color(storage, 25) == style.code)
    }

    @Test func leavesBareAndUnknownFencesInTheCodeColor() {
        for text in ["```\nlet x\n```", "```nope\nlet x\n```", "```mermaid\ngraph TD\n```"] {
            let storage = storage(text)
            let content = (text as NSString).range(of: "\n").location + 1
            #expect(color(storage, content) == style.code, "\(text)")
        }
    }

    @Test func worksInTheInlinePresentation() {
        let storage = storage(swift, inline: true)
        #expect(color(storage, 9) == style.color(for: .keyword))
        #expect(color(storage, 13) == style.foreground)
        #expect(color(storage, 19) == style.color(for: .comment))
        #expect(storage.attribute(.blockDecoration, at: 9, effectiveRange: nil) as? String == "code")
        #expect(color(storage, 0) == style.muted)
    }

    @Test func mapsTokensLineByLine() {
        // "```c\n" 0–4, "/* a\n" 5–9, " b */\n" 10–15, "```" 16–18.
        let storage = storage("```c\n/* a\n b */\n```")
        #expect(color(storage, 5) == style.color(for: .comment))
        #expect(color(storage, 8) == style.color(for: .comment))
        #expect(color(storage, 9) == style.foreground)
        #expect(color(storage, 11) == style.color(for: .comment))
        #expect(color(storage, 14) == style.color(for: .comment))
    }

    @Test func colorsAnUnclosedFenceAndDiffLines() {
        // "```diff\n" 0–7, "- old\n" 8–13, "+ new" 14–18.
        let storage = storage("```diff\n- old\n+ new")
        #expect(color(storage, 8) == style.color(for: .deletion))
        #expect(color(storage, 14) == style.color(for: .addition))
        #expect((storage.attribute(.backgroundColor, at: 14, effectiveRange: nil) as? NSColor)?.alphaComponent == 0.12)
    }

    @Test func stylesFollowTheThemeAndAppearance() {
        #expect(EditorStyle(theme: .macOS, isDark: false).color(for: .keyword) == NSColor(rgb: 0x9B2393))
        #expect(EditorStyle(theme: .macOS, isDark: true).color(for: .keyword) == NSColor(rgb: 0xFC5FA3))
        #expect(EditorStyle(theme: .solarized, isDark: true).color(for: .string) == NSColor(rgb: 0x2AA198))
    }

    @Test func textViewColorsCodeInBothPresentations() {
        let view = ThemedTextView.standalone()
        view.string = swift
        view.rehighlight()
        #expect(color(view.textStorage!, 9) == view.style.color(for: .keyword))
        view.presentation = .inline
        #expect(color(view.textStorage!, 9) == view.style.color(for: .keyword))
        view.theme = .solarized
        #expect(color(view.textStorage!, 9) == NSColor(rgb: 0x859900))
    }
}
