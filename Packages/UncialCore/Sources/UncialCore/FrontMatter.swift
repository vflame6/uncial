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

    static func renderBlock(_ frontMatter: String) -> String {
        let trimmed = frontMatter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "<pre class=\"front-matter\">\(HTMLEscaping.escape(trimmed))</pre>\n"
    }

    private static func isDelimiter(_ line: Substring, allowDots: Bool) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "---" || (allowDots && trimmed == "...")
    }
}
