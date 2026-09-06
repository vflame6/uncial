import Foundation

/// Finds the Markdown constructs worth coloring in the source editor. Line-based with just
/// enough state for fenced code and a leading front-matter block; inline code is masked before
/// emphasis and links are matched so `*` inside backticks stays code.
nonisolated enum MarkdownHighlighter {
    enum Kind: Equatable {
        case heading, strong, emphasis, inlineCode, codeBlock, link, url, listMarker, quote, rule, frontMatter
    }

    struct Span: Equatable {
        let range: NSRange
        let kind: Kind
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static let fence = regex(#"^\s{0,3}(`{3,}|~{3,})"#)
    private static let rule = regex(#"^\s{0,3}([-*_])(\s*\1){2,}\s*$"#)
    private static let heading = regex(#"^\s{0,3}#{1,6}(\s|$)"#)
    private static let quote = regex(#"^\s{0,3}>"#)
    private static let listMarker = regex(#"^\s*(?:[-+*]|\d{1,9}[.)])\s+(?:\[[ xX]\]\s+)?"#)
    private static let frontMatterOpen = regex(#"^---\s*$"#)
    private static let frontMatterClose = regex(#"^(---|\.\.\.)\s*$"#)
    private static let inlineCode = regex(#"`+[^`\n]+`+"#)
    private static let strong = regex(#"\*\*[^*\n]+\*\*|__[^_\n]+__"#)
    private static let emphasis = regex(#"(?<![\w*])\*[^*\n]+\*(?![\w*])|(?<![\w_])_[^_\n]+_(?![\w_])"#)
    private static let link = regex(#"(!?\[[^\]\n]*\])(\([^)\n]*\))"#)
    private static let autolink = regex(#"<(?:https?|mailto):[^>\s]+>"#)

    static func spans(in text: String) -> [Span] {
        let source = text as NSString
        let length = source.length
        var spans: [Span] = []
        var fenceMarker: String?
        var inFrontMatter = false
        var isFirstLine = true
        var location = 0

        while location < length {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            source.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let contentRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let line = source.substring(with: contentRange)
            let whole = NSRange(location: 0, length: (line as NSString).length)
            defer {
                isFirstLine = false
                location = lineEnd
            }

            if isFirstLine, frontMatterOpen.firstMatch(in: line, range: whole) != nil {
                inFrontMatter = true
                spans.append(Span(range: contentRange, kind: .frontMatter))
                continue
            }
            if inFrontMatter {
                spans.append(Span(range: contentRange, kind: .frontMatter))
                if frontMatterClose.firstMatch(in: line, range: whole) != nil { inFrontMatter = false }
                continue
            }
            if let match = fence.firstMatch(in: line, range: whole) {
                let marker = (line as NSString).substring(with: match.range(at: 1))
                if let open = fenceMarker {
                    if marker.first == open.first, marker.count >= open.count { fenceMarker = nil }
                } else {
                    fenceMarker = marker
                }
                spans.append(Span(range: contentRange, kind: .codeBlock))
                continue
            }
            if fenceMarker != nil {
                spans.append(Span(range: contentRange, kind: .codeBlock))
                continue
            }
            if rule.firstMatch(in: line, range: whole) != nil {
                spans.append(Span(range: contentRange, kind: .rule))
                continue
            }
            if heading.firstMatch(in: line, range: whole) != nil {
                spans.append(Span(range: contentRange, kind: .heading))
                continue
            }
            if quote.firstMatch(in: line, range: whole) != nil {
                spans.append(Span(range: contentRange, kind: .quote))
                continue
            }
            if let match = listMarker.firstMatch(in: line, range: whole) {
                spans.append(Span(range: NSRange(location: lineStart + match.range.location, length: match.range.length), kind: .listMarker))
            }
            spans += inlineSpans(in: line, offset: lineStart)
        }
        return spans
    }

    private static func inlineSpans(in line: String, offset: Int) -> [Span] {
        var spans: [Span] = []
        let scratch = NSMutableString(string: line)
        let whole = NSRange(location: 0, length: scratch.length)

        func mask(_ range: NSRange) {
            scratch.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        func shifted(_ range: NSRange) -> NSRange {
            NSRange(location: offset + range.location, length: range.length)
        }

        for match in inlineCode.matches(in: line, range: whole) {
            spans.append(Span(range: shifted(match.range), kind: .inlineCode))
            mask(match.range)
        }
        for match in autolink.matches(in: scratch as String, range: whole) {
            spans.append(Span(range: shifted(match.range), kind: .url))
            mask(match.range)
        }
        for match in link.matches(in: scratch as String, range: whole) {
            spans.append(Span(range: shifted(match.range(at: 1)), kind: .link))
            spans.append(Span(range: shifted(match.range(at: 2)), kind: .url))
            mask(match.range(at: 2))
        }
        for match in strong.matches(in: scratch as String, range: whole) {
            spans.append(Span(range: shifted(match.range), kind: .strong))
            mask(match.range)
        }
        for match in emphasis.matches(in: scratch as String, range: whole) {
            spans.append(Span(range: shifted(match.range), kind: .emphasis))
        }
        return spans
    }
}
