import Foundation

/// YAML front matter: a leading block delimited by `---` lines (closing may be `---` or `...`).
public enum FrontMatter {
    public static func split(_ markdown: String) -> (frontMatter: String?, body: String) {
        var text = Substring(markdown)
        if text.hasPrefix("\u{FEFF}") { text = text.dropFirst() }
        // "\r\n" is a single Character in Swift, so match both line endings explicitly.
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" })
        guard let first = lines.first, isDelimiter(first, allowDots: false) else {
            return (nil, String(text))
        }
        guard let closing = lines.dropFirst().firstIndex(where: { isDelimiter($0, allowDots: true) }) else {
            return (nil, String(text))
        }
        let frontMatter = lines[1..<closing].joined(separator: "\n")
        lines.removeSubrange(0...closing)
        return (frontMatter, lines.joined(separator: "\n"))
    }

    /// How many leading lines `split` removes: the delimiters plus the block, 0 without front matter.
    public static func bodyLineOffset(of markdown: String) -> Int {
        var text = Substring(markdown)
        if text.hasPrefix("\u{FEFF}") { text = text.dropFirst() }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" })
        guard let first = lines.first, isDelimiter(first, allowDots: false),
              let closing = lines.dropFirst().firstIndex(where: { isDelimiter($0, allowDots: true) }) else { return 0 }
        return closing + 1
    }

    static func renderBlock(_ frontMatter: String) -> String {
        let trimmed = frontMatter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "<pre class=\"front-matter\">\(HTMLEscaping.escape(trimmed))</pre>\n"
    }

    /// `---` (or `...` to close) in the line's first column, trailing whitespace allowed: an indented
    /// `---` is YAML content, a block scalar's text for one (BUG-17).
    private static func isDelimiter(_ line: Substring, allowDots: Bool) -> Bool {
        var end = line.endIndex
        while end > line.startIndex, line[line.index(before: end)].isWhitespace {
            end = line.index(before: end)
        }
        let content = line[..<end]
        return content == "---" || (allowDots && content == "...")
    }
}
