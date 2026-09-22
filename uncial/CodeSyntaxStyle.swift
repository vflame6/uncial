import AppKit
import UncialCore

/// Colors the code inside fenced blocks whose info string names a language `CodeHighlighter`
/// knows, in both presentations: the block's text takes the foreground color (like the page's
/// `pre`) and every token its scope's color from the theme's `SyntaxPalette`; the fence lines and
/// blocks in unknown languages keep the code color the Markdown coloring gave them.
enum CodeSyntaxStyle {
    /// Longer blocks stay in the code color: this runs on every edit.
    static let blockLimit = 30_000

    static func apply(_ tokens: [MarkdownHighlighter.Token], to storage: NSTextStorage, style: EditorStyle) {
        let text = storage.string as NSString
        var language: String?
        var lines: [NSRange] = []
        func flush() {
            defer {
                language = nil
                lines = []
            }
            guard let language, !lines.isEmpty, CodeHighlighter.supports(language) else { return }
            let content = NSRange(location: lines[0].location, length: NSMaxRange(lines[lines.count - 1]) - lines[0].location)
            guard content.length <= blockLimit, NSMaxRange(content) <= text.length else { return }
            color(lines, of: text, language: language, in: storage, style: style)
        }
        for token in tokens {
            switch token.kind {
            case .fence:
                if language != nil {
                    flush()
                } else {
                    let markerEnd = token.markers.first.map { NSMaxRange($0) } ?? token.range.location
                    let info = text.substring(with: NSRange(location: markerEnd, length: max(0, NSMaxRange(token.range) - markerEnd)))
                    language = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
                }
            case .code:
                if language != nil { lines.append(token.range) }
            default:
                break
            }
        }
        flush()
    }

    /// The tokens come from the lines joined with `\n` and never cross a line, so each one maps
    /// back through the line it starts in, whatever line breaks the text itself uses.
    private static func color(_ lines: [NSRange], of text: NSString, language: String, in storage: NSTextStorage, style: EditorStyle) {
        let code = lines.map { text.substring(with: $0) }.joined(separator: "\n")
        var starts: [(code: Int, text: Int)] = []
        var offset = 0
        for line in lines {
            starts.append((offset, line.location))
            offset += line.length + 1
        }
        let content = NSRange(location: lines[0].location, length: NSMaxRange(lines[lines.count - 1]) - lines[0].location)
        storage.addAttribute(.foregroundColor, value: style.foreground, range: content)
        for token in CodeHighlighter.tokens(in: code, language: language) {
            var low = 0
            var high = starts.count - 1
            while low < high {
                let middle = (low + high + 1) / 2
                if starts[middle].code <= token.range.location { low = middle } else { high = middle - 1 }
            }
            let range = NSRange(location: starts[low].text + (token.range.location - starts[low].code), length: token.range.length)
            guard NSMaxRange(range) <= NSMaxRange(content) else { continue }
            let color = style.color(for: token.scope)
            storage.addAttribute(.foregroundColor, value: color, range: range)
            if token.scope == .addition || token.scope == .deletion {
                storage.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.12), range: range)
            }
        }
    }
}
