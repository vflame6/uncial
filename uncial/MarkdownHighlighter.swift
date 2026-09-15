import Foundation

/// Finds the Markdown constructs the editor styles. Line-based with just enough state for fenced
/// code and a leading front-matter block; inline code is masked before the other inline
/// constructs are matched so `*` inside backticks stays code. `tokens(in:)` is the full picture
/// (each construct with its delimiter ranges); `spans(in:)` is the flat coloring view of it.
nonisolated enum MarkdownHighlighter {
    enum Kind: Equatable {
        case heading, strong, emphasis, strikethrough, inlineCode, codeBlock, link, url, listMarker, quote, rule, frontMatter
    }

    struct Span: Equatable {
        let range: NSRange
        let kind: Kind
    }

    struct Token: Equatable {
        enum Kind: Equatable {
            case heading(level: Int)
            case strong, emphasis, strikethrough, inlineCode
            case link(destination: String)
            case image
            case autolink(destination: String)
            /// `bullet` is the character index of a `-`, `*` or `+` marker; nil for numbered items.
            case listItem(bullet: Int?)
            case quote(depth: Int)
            case rule
            case fence
            case code
            case frontMatter
        }

        /// A whole line (without its break) for block kinds, the delimited text for inline kinds,
        /// the marker prefix for list items.
        let range: NSRange
        let kind: Kind
        /// Delimiters in document order: what the inline presentation hides.
        let markers: [NSRange]
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static let fence = regex(#"^\s{0,3}(`{3,}|~{3,})"#)
    private static let rule = regex(#"^\s{0,3}([-*_])(\s*\1){2,}\s*$"#)
    private static let heading = regex(#"^\s{0,3}(#{1,6})(?:[ \t]+|$)"#)
    private static let quote = regex(#"^(?:[ \t]{0,3}>[ \t]?)+"#)
    private static let listMarker = regex(#"^\s*([-+*]|\d{1,9}[.)])\s+(?:\[[ xX]\]\s+)?"#)
    private static let frontMatterOpen = regex(#"^---\s*$"#)
    private static let frontMatterClose = regex(#"^(---|\.\.\.)\s*$"#)
    private static let inlineCode = regex(#"(`+)[^`\n]+(`+)"#)
    private static let strong = regex(#"\*\*[^*\n]+\*\*|__[^_\n]+__"#)
    private static let emphasis = regex(#"(?<![\w*])\*[^*\n]+\*(?![\w*])|(?<![\w_])_[^_\n]+_(?![\w_])"#)
    private static let strikethrough = regex(#"~~[^~\n]+~~"#)
    private static let link = regex(#"(!?\[[^\]\n]*\])(\([^)\n]*\))"#)
    private static let autolink = regex(#"<(?:https?|mailto):[^>\s]+>"#)

    static func spans(in text: String) -> [Span] {
        spans(from: tokens(in: text))
    }

    static func tokens(in text: String) -> [Token] {
        let source = text as NSString
        let length = source.length
        var tokens: [Token] = []
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
            func shifted(_ range: NSRange) -> NSRange {
                NSRange(location: lineStart + range.location, length: range.length)
            }

            if isFirstLine, frontMatterOpen.firstMatch(in: line, range: whole) != nil {
                inFrontMatter = true
                tokens.append(Token(range: contentRange, kind: .frontMatter, markers: []))
                continue
            }
            if inFrontMatter {
                tokens.append(Token(range: contentRange, kind: .frontMatter, markers: []))
                if frontMatterClose.firstMatch(in: line, range: whole) != nil { inFrontMatter = false }
                continue
            }
            if let match = fence.firstMatch(in: line, range: whole) {
                let marker = (line as NSString).substring(with: match.range(at: 1))
                if let open = fenceMarker {
                    guard marker.first == open.first, marker.count >= open.count else {
                        tokens.append(Token(range: contentRange, kind: .code, markers: []))
                        continue
                    }
                    fenceMarker = nil
                } else {
                    fenceMarker = marker
                }
                tokens.append(Token(range: contentRange, kind: .fence, markers: [shifted(match.range(at: 1))]))
                continue
            }
            if fenceMarker != nil {
                tokens.append(Token(range: contentRange, kind: .code, markers: []))
                continue
            }
            if rule.firstMatch(in: line, range: whole) != nil {
                tokens.append(Token(range: contentRange, kind: .rule, markers: [contentRange]))
                continue
            }
            if let match = heading.firstMatch(in: line, range: whole) {
                tokens.append(Token(range: contentRange, kind: .heading(level: match.range(at: 1).length), markers: [shifted(match.range)]))
                tokens += inlineTokens(in: line, offset: lineStart, from: match.range.length)
                continue
            }
            if let match = quote.firstMatch(in: line, range: whole) {
                let prefix = (line as NSString).substring(with: match.range) as NSString
                var markers: [NSRange] = []
                var index = 0
                while index < prefix.length {
                    guard prefix.character(at: index) == 0x3E else { // ">"
                        index += 1
                        continue
                    }
                    let spaced = index + 1 < prefix.length && prefix.character(at: index + 1) != 0x3E
                    markers.append(NSRange(location: lineStart + index, length: spaced ? 2 : 1))
                    index += spaced ? 2 : 1
                }
                tokens.append(Token(range: contentRange, kind: .quote(depth: markers.count), markers: markers))
                tokens += inlineTokens(in: line, offset: lineStart, from: match.range.length)
                continue
            }
            if let match = listMarker.firstMatch(in: line, range: whole) {
                let marker = match.range(at: 1)
                let isBullet = marker.length == 1 && "-+*".contains((line as NSString).substring(with: marker))
                tokens.append(Token(range: shifted(match.range), kind: .listItem(bullet: isBullet ? lineStart + marker.location : nil), markers: []))
                tokens += inlineTokens(in: line, offset: lineStart, from: match.range.length)
                continue
            }
            tokens += inlineTokens(in: line, offset: lineStart, from: 0)
        }
        return tokens
    }

    /// Inline constructs of `line` from `start` on, in document order, ranges shifted by `offset`.
    private static func inlineTokens(in line: String, offset: Int, from start: Int) -> [Token] {
        let scratch = NSMutableString(string: line)
        let region = NSRange(location: start, length: scratch.length - start)
        var tokens: [Token] = []

        func mask(_ range: NSRange) {
            scratch.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        func shifted(_ range: NSRange) -> NSRange {
            NSRange(location: offset + range.location, length: range.length)
        }
        func edges(_ range: NSRange, open: Int, close: Int) -> [NSRange] {
            [NSRange(location: offset + range.location, length: open),
             NSRange(location: offset + NSMaxRange(range) - close, length: close)]
        }

        for match in inlineCode.matches(in: line, range: region) {
            tokens.append(Token(range: shifted(match.range), kind: .inlineCode, markers: edges(match.range, open: match.range(at: 1).length, close: match.range(at: 2).length)))
            mask(match.range)
        }
        for match in autolink.matches(in: scratch as String, range: region) {
            let inner = NSRange(location: match.range.location + 1, length: match.range.length - 2)
            tokens.append(Token(range: shifted(match.range), kind: .autolink(destination: scratch.substring(with: inner)), markers: edges(match.range, open: 1, close: 1)))
            mask(match.range)
        }
        for match in link.matches(in: scratch as String, range: region) {
            let isImage = scratch.character(at: match.range.location) == 0x21 // "!"
            let close = match.range(at: 2)
            let markers = [NSRange(location: offset + match.range.location, length: isImage ? 2 : 1),
                           NSRange(location: offset + close.location - 1, length: close.length + 1)]
            let target = scratch.substring(with: NSRange(location: close.location + 1, length: close.length - 2))
                .trimmingCharacters(in: .whitespaces)
            let destination = String(target.split(separator: " ", maxSplits: 1).first ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            tokens.append(Token(range: shifted(match.range), kind: isImage ? .image : .link(destination: destination), markers: markers))
            mask(close)
        }
        for match in strong.matches(in: scratch as String, range: region) {
            tokens.append(Token(range: shifted(match.range), kind: .strong, markers: edges(match.range, open: 2, close: 2)))
            mask(match.range)
        }
        for match in emphasis.matches(in: scratch as String, range: region) {
            tokens.append(Token(range: shifted(match.range), kind: .emphasis, markers: edges(match.range, open: 1, close: 1)))
        }
        for match in strikethrough.matches(in: scratch as String, range: region) {
            tokens.append(Token(range: shifted(match.range), kind: .strikethrough, markers: edges(match.range, open: 2, close: 2)))
        }
        return tokens.sorted { $0.range.location < $1.range.location }
    }

    static func spans(from tokens: [Token]) -> [Span] {
        var spans: [Span] = []
        for token in tokens {
            switch token.kind {
            case .heading: spans.append(Span(range: token.range, kind: .heading))
            case .strong: spans.append(Span(range: token.range, kind: .strong))
            case .emphasis: spans.append(Span(range: token.range, kind: .emphasis))
            case .strikethrough: spans.append(Span(range: token.range, kind: .strikethrough))
            case .inlineCode: spans.append(Span(range: token.range, kind: .inlineCode))
            case .link, .image:
                let close = token.markers[1]
                spans.append(Span(range: NSRange(location: token.range.location, length: close.location + 1 - token.range.location), kind: .link))
                spans.append(Span(range: NSRange(location: close.location + 1, length: close.length - 1), kind: .url))
            case .autolink: spans.append(Span(range: token.range, kind: .url))
            case .listItem: spans.append(Span(range: token.range, kind: .listMarker))
            case .quote: spans.append(Span(range: token.range, kind: .quote))
            case .rule: spans.append(Span(range: token.range, kind: .rule))
            case .fence, .code: spans.append(Span(range: token.range, kind: .codeBlock))
            case .frontMatter: spans.append(Span(range: token.range, kind: .frontMatter))
            }
        }
        return spans
    }
}
