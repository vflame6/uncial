import Foundation
import UncialCore

/// Finds the Markdown constructs the editor styles. Line-based with one line of lookahead
/// (tables, setext headings) and just enough state for fenced code and a leading front-matter
/// block; inline code is masked before the other inline constructs are matched so `*` inside
/// backticks stays code. `tokens(in:)` is the full picture (each construct with its delimiter
/// ranges); `spans(in:)` is the flat coloring view of it.
nonisolated enum MarkdownHighlighter {
    enum Kind: Equatable {
        case heading, strong, emphasis, strikethrough, inlineCode, codeBlock, link, url, listMarker, quote, rule, frontMatter, table, html, math, callout
    }

    struct Span: Equatable {
        let range: NSRange
        let kind: Kind
    }

    enum TableAlignment: Equatable {
        case left, center, right
    }

    /// One cell of a table row: the text between two pipes (spaces included), how many of its
    /// characters show in the inline presentation, the width its column needs, the alignment.
    struct TableCell: Equatable {
        let range: NSRange
        let visibleWidth: Int
        let columnWidth: Int
        let alignment: TableAlignment
    }

    struct Token: Equatable {
        enum Kind: Equatable {
            case heading(level: Int)
            /// The `===`/`---` under a setext heading.
            case headingUnderline
            case strong, emphasis, strikethrough, inlineCode
            case link(destination: String)
            case image(destination: String)
            case autolink(destination: String)
            case footnoteReference
            /// The `[^id]:` prefix of a footnote line.
            case footnoteDefinition
            /// An HTML element on one line with both tags as markers, a lone tag (`<br>`, an unmatched
            /// `<div …>` or `</div>`) or, with `element` nil, a comment. Attribute names are lowercase.
            case html(element: String?, attributes: [String: String])
            /// A `[label]: destination` line.
            case linkDefinition
            /// A backslash before ASCII punctuation; the backslash is the marker.
            case escape
            /// `$…$` (inline) or `$$…$$` (display) with the dollars as markers; a line inside a `$$` block
            /// is display math without markers.
            case math(display: Bool)
            /// A `$$` line opening or closing a math block; the dollars are the marker.
            case mathFence
            /// `bullet` is the character index of a `-`, `*` or `+` marker (nil for numbered items);
            /// `box` the three characters of a task box `[ ]`/`[x]`, whose brackets are markers.
            case listItem(bullet: Int?, box: NSRange?)
            case quote(depth: Int)
            /// The first line of a callout (`Callouts`): a quote line starting with `[!type]` where its
            /// blockquote begins. `type` is the default type it maps to, `defaultTitle` what shows when the
            /// line has no title; the markers are the `>` prefix and the marker with its following space.
            case callout(type: String, depth: Int, defaultTitle: String)
            case rule
            case fence
            case code
            case frontMatter
            /// `pipes` are the character indexes of every `|` in the row, outer ones included.
            case tableRow(cells: [TableCell], isHeader: Bool, pipes: [Int])
            case tableDelimiter
        }

        /// A whole line (without its break) for block kinds, the delimited text for inline kinds,
        /// the marker prefix for list items and footnote definitions.
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
    private static let setextUnderline = regex(#"^\s{0,3}(=+|-+)\s*$"#)
    private static let quote = regex(#"^(?:[ \t]{0,3}>[ \t]?)+"#)
    private static let listMarker = regex(#"^\s*([-+*]|\d{1,9}[.)])\s+(?:(\[[ xX]\])\s+)?"#)
    private static let frontMatterOpen = regex(#"^---\s*$"#)
    private static let frontMatterClose = regex(#"^(---|\.\.\.)\s*$"#)
    private static let footnoteDefinition = regex(#"^\[\^[^\]\s]+\]:"#)
    private static let tableDelimiter = regex(#"^\s{0,3}\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?\s*$"#)
    private static let pipe = regex(#"(?<!\\)\|"#)
    // Emphasis needs text right inside its markers (`* 3 *` is arithmetic) and no backslash before them.
    private static let boldItalic = regex(#"(?<![\w*\\])\*\*\*(?!\s)[^*\n]+(?<![\s\\])\*\*\*(?![\w*])"#)
    private static let strong = regex(#"(?<!\\)\*\*(?!\s)[^*\n]+(?<![\s\\])\*\*|(?<!\\)__(?!\s)[^_\n]+(?<![\s\\])__"#)
    private static let emphasis = regex(#"(?<![\w*\\])\*(?!\s)[^*\n]+(?<![\s\\])\*(?![\w*])|(?<![\w_\\])_(?!\s)[^_\n]+(?<![\s\\])_(?![\w_])"#)
    private static let strikethrough = regex(#"~~[^~\n]+~~"#)
    private static let autolink = regex(#"<(?:https?|mailto):[^>\s]+>"#)
    private static let footnoteReference = regex(#"\[\^[^\]\s]+\](?!:)"#)
    private static let html = regex(#"<!--.*?-->|<(/?)([A-Za-z][A-Za-z0-9-]*)((?:\s[^<>\n]*)?)(/?)>"#)
    private static let attribute = regex(#"([A-Za-z_:][-A-Za-z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?"#)
    /// Tags that never have content: a lone `<br>` needs no `</br>`.
    private static let voidElements: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
    private static let linkDefinition = regex(#"^\s{0,3}\[([^\]\n]+)\]:\s*(?:<([^>\n]*)>|(\S+))"#)
    private static let referenceLink = regex(#"(!?)\[([^\[\]\n]+)\](?:\[([^\[\]\n]*)\])?"#)
    private static let escape = regex(#"\\[!-/:-@\[-`{-~]"#)
    private static let mathFence = regex(#"^\s{0,3}\$\$\s*$"#)
    private static let displayMath = regex(#"\$\$([^$\n]+?)\$\$"#)
    // GitHub's rules: no space right inside the dollars, no digit right after the closing one.
    private static let inlineMath = regex(#"(?<![\w$\\])\$(?![\s$])([^$\n]+?)(?<![\s\\])\$(?![\d$])"#)

    static func spans(in text: String) -> [Span] {
        spans(from: tokens(in: text))
    }

    static func tokens(in text: String) -> [Token] {
        let source = text as NSString
        let lines = lineRanges(of: source)
        var tokens: [Token] = []
        var fenceMarker: String?
        var inMathBlock = false
        var inFrontMatter = false
        var index = 0
        let definitions = linkDefinitions(in: lines, source: source)

        while index < lines.count {
            let current = index
            index += 1
            let contentRange = lines[current]
            let lineStart = contentRange.location
            let line = source.substring(with: contentRange)
            let whole = NSRange(location: 0, length: (line as NSString).length)
            func shifted(_ range: NSRange) -> NSRange {
                NSRange(location: lineStart + range.location, length: range.length)
            }

            if current == 0, frontMatterOpen.firstMatch(in: line, range: whole) != nil {
                inFrontMatter = true
                tokens.append(Token(range: contentRange, kind: .frontMatter, markers: []))
                continue
            }
            if inFrontMatter {
                tokens.append(Token(range: contentRange, kind: .frontMatter, markers: []))
                if frontMatterClose.firstMatch(in: line, range: whole) != nil { inFrontMatter = false }
                continue
            }
            // CommonMark: a backtick fence's info string has no backticks (```npm install``` is inline
            // code), and a closing fence has no info string (```js in an open block is content).
            if let match = fence.firstMatch(in: line, range: whole),
               fenceMarker != nil || !isInlineCodeLine(line, marker: match.range(at: 1)) {
                let marker = (line as NSString).substring(with: match.range(at: 1))
                if let open = fenceMarker {
                    let rest = (line as NSString).substring(from: NSMaxRange(match.range(at: 1)))
                    guard marker.first == open.first, marker.count >= open.count,
                          rest.allSatisfy({ $0 == " " || $0 == "\t" }) else {
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
            if mathFence.firstMatch(in: line, range: whole) != nil {
                inMathBlock.toggle()
                tokens.append(Token(range: contentRange, kind: .mathFence, markers: [shifted((line as NSString).range(of: "$$"))]))
                continue
            }
            if inMathBlock {
                tokens.append(Token(range: contentRange, kind: .math(display: true), markers: []))
                continue
            }
            if rule.firstMatch(in: line, range: whole) != nil {
                tokens.append(Token(range: contentRange, kind: .rule, markers: [contentRange]))
                continue
            }
            if let match = heading.firstMatch(in: line, range: whole) {
                tokens.append(Token(range: contentRange, kind: .heading(level: match.range(at: 1).length), markers: [shifted(match.range)]))
                tokens += inlineTokens(in: line, offset: lineStart, from: match.range.length, definitions: definitions)
                continue
            }
            if let match = quote.firstMatch(in: line, range: whole) {
                let prefix = (line as NSString).substring(with: match.range) as NSString
                var markers: [NSRange] = []
                var position = 0
                while position < prefix.length {
                    guard prefix.character(at: position) == 0x3E else { // ">"
                        position += 1
                        continue
                    }
                    let spaced = position + 1 < prefix.length && prefix.character(at: position + 1) != 0x3E
                    markers.append(NSRange(location: lineStart + position, length: spaced ? 2 : 1))
                    position += spaced ? 2 : 1
                }
                // `[!type]` opens a callout where its blockquote begins: on a line deeper than the one before.
                var restStart = match.range.length
                while restStart < whole.length, restStart - match.range.length < 3, [0x20, 0x09].contains((line as NSString).character(at: restStart)) {
                    restStart += 1
                }
                if let marker = Callouts.marker(in: (line as NSString).substring(from: restStart)),
                   markers.count > quoteDepth(ofLineBefore: current, lines: lines, source: source) {
                    let kind = Token.Kind.callout(type: marker.type, depth: markers.count, defaultTitle: marker.defaultTitle)
                    tokens.append(Token(range: contentRange, kind: kind, markers: markers + [NSRange(location: lineStart + restStart, length: marker.length)]))
                    tokens += inlineTokens(in: line, offset: lineStart, from: restStart + marker.length, definitions: definitions)
                    continue
                }
                tokens.append(Token(range: contentRange, kind: .quote(depth: markers.count), markers: markers))
                tokens += inlineTokens(in: line, offset: lineStart, from: match.range.length, definitions: definitions)
                continue
            }
            if let match = listMarker.firstMatch(in: line, range: whole) {
                let marker = match.range(at: 1)
                let isBullet = marker.length == 1 && "-+*".contains((line as NSString).substring(with: marker))
                let box = match.range(at: 2).location == NSNotFound ? nil : shifted(match.range(at: 2))
                let markers = box.map { [NSRange(location: $0.location, length: 1), NSRange(location: $0.location + 2, length: 1)] } ?? []
                tokens.append(Token(range: shifted(match.range), kind: .listItem(bullet: isBullet ? lineStart + marker.location : nil, box: box), markers: markers))
                tokens += inlineTokens(in: line, offset: lineStart, from: match.range.length, definitions: definitions)
                continue
            }
            if line.contains("|"), let table = tableTokens(startingAt: current, lines: lines, source: source, definitions: definitions) {
                tokens += table.tokens
                index = table.nextLine
                continue
            }
            if let match = footnoteDefinition.firstMatch(in: line, range: whole) {
                tokens.append(Token(range: shifted(match.range), kind: .footnoteDefinition, markers: []))
                tokens += inlineTokens(in: line, offset: lineStart, from: match.range.length, definitions: definitions)
                continue
            }
            if linkDefinition.firstMatch(in: line, range: whole) != nil {
                tokens.append(Token(range: contentRange, kind: .linkDefinition, markers: []))
                continue
            }
            // Setext heading: a plain, non-empty line whose next line is `===` or `---`.
            if whole.length > 0, index < lines.count {
                let underline = source.substring(with: lines[index])
                if setextUnderline.firstMatch(in: underline, range: NSRange(location: 0, length: (underline as NSString).length)) != nil {
                    tokens.append(Token(range: contentRange, kind: .heading(level: underline.contains("=") ? 1 : 2), markers: []))
                    tokens += inlineTokens(in: line, offset: lineStart, from: 0, definitions: definitions)
                    tokens.append(Token(range: lines[index], kind: .headingUnderline, markers: [lines[index]]))
                    index += 1
                    continue
                }
            }
            tokens += inlineTokens(in: line, offset: lineStart, from: 0, definitions: definitions)
        }
        return tokens
    }

    /// The blocks Markdown takes literally, one range per block from its first line to the end of its
    /// last: front matter, fenced code with its fences, and `$$` blocks. Display math on an ordinary
    /// line (with its dollars as markers) is not one.
    static func literalBlocks(in tokens: [Token]) -> [NSRange] {
        var blocks: [NSRange] = []
        var inFrontMatter = false, inFence = false, inMath = false
        func extend(_ range: NSRange) {
            blocks[blocks.count - 1] = NSUnionRange(blocks[blocks.count - 1], range)
        }
        for token in tokens {
            switch token.kind {
            case .frontMatter:
                if inFrontMatter { extend(token.range) } else { blocks.append(token.range) }
                inFrontMatter = true
            case .fence:
                if inFence { extend(token.range) } else { blocks.append(token.range) }
                inFence.toggle()
            case .code where inFence:
                extend(token.range)
            case .mathFence:
                if inMath { extend(token.range) } else { blocks.append(token.range) }
                inMath.toggle()
            case .math(display: true) where inMath && token.markers.isEmpty:
                extend(token.range)
            default:
                inFrontMatter = false
            }
        }
        return blocks
    }

    /// Whether a line that starts with a backtick fence marker has a backtick after it, which makes it
    /// a line of inline code rather than an opening fence.
    private static func isInlineCodeLine(_ line: String, marker: NSRange) -> Bool {
        let text = line as NSString
        return text.substring(with: marker).first == "`" && text.substring(from: NSMaxRange(marker)).contains("`")
    }

    /// The quote depth of the line before `index` (0 for the first line and for lines without a `>` prefix).
    private static func quoteDepth(ofLineBefore index: Int, lines: [NSRange], source: NSString) -> Int {
        guard index > 0 else { return 0 }
        let line = source.substring(with: lines[index - 1])
        guard let match = quote.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return 0 }
        return (line as NSString).substring(with: match.range).filter { $0 == ">" }.count
    }

    /// A callout's lines: its first line and the quote lines right after it at its depth or deeper,
    /// up to a line that is not one (a lazy continuation line ends it here, unlike in cmark).
    struct CalloutBlock: Equatable {
        let range: NSRange
        let type: String
        let depth: Int
    }

    static func calloutBlocks(in tokens: [Token], text: NSString) -> [CalloutBlock] {
        var blocks: [CalloutBlock] = []
        for (index, token) in tokens.enumerated() {
            guard case .callout(let type, let depth, _) = token.kind else { continue }
            var end = NSMaxRange(token.range)
            for next in tokens[(index + 1)...] {
                let lineDepth: Int
                switch next.kind {
                case .quote(let depth): lineDepth = depth
                case .callout(_, let depth, _): lineDepth = depth
                default: continue
                }
                guard end < text.length, lineDepth >= depth,
                      next.range.location == NSMaxRange(text.paragraphRange(for: NSRange(location: end, length: 0))) else { break }
                end = NSMaxRange(next.range)
            }
            blocks.append(CalloutBlock(range: NSRange(location: token.range.location, length: end - token.range.location), type: type, depth: depth))
        }
        return blocks
    }

    /// Reference link definitions anywhere in the document, keyed by their normalized label
    /// (case-folded, inner whitespace collapsed), which is how `[text][label]` finds its destination.
    private static func linkDefinitions(in lines: [NSRange], source: NSString) -> [String: String] {
        var definitions: [String: String] = [:]
        for range in lines {
            let line = source.substring(with: range)
            guard let match = linkDefinition.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { continue }
            let text = line as NSString
            let destination = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
            let label = normalized(label: text.substring(with: match.range(at: 1)))
            if definitions[label] == nil {
                definitions[label] = text.substring(with: destination)
            }
        }
        return definitions
    }

    private static func normalized(label: String) -> String {
        label.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Content ranges of every line (without line breaks), in order.
    private static func lineRanges(of source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = 0
        while location < source.length {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            source.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            ranges.append(NSRange(location: lineStart, length: contentsEnd - lineStart))
            location = lineEnd
        }
        return ranges
    }

    // MARK: - Tables

    private struct TableParse {
        let tokens: [Token]
        let nextLine: Int
    }

    /// A header row followed by a delimiter row with the same number of cells, then rows until a
    /// blank line or a line without a pipe. Column widths are the widest visible cell per column.
    private static func tableTokens(startingAt headerIndex: Int, lines: [NSRange], source: NSString, definitions: [String: String]) -> TableParse? {
        guard headerIndex + 1 < lines.count else { return nil }
        let delimiterRange = lines[headerIndex + 1]
        let delimiter = source.substring(with: delimiterRange)
        guard tableDelimiter.firstMatch(in: delimiter, range: NSRange(location: 0, length: (delimiter as NSString).length)) != nil else { return nil }
        let headerCells = cellRanges(in: source.substring(with: lines[headerIndex]))
        let alignmentCells = cellRanges(in: delimiter)
        guard !headerCells.isEmpty, headerCells.count == alignmentCells.count else { return nil }
        let alignments: [TableAlignment] = alignmentCells.map { cell in
            let spec = (delimiter as NSString).substring(with: cell).trimmingCharacters(in: .whitespaces)
            switch (spec.hasPrefix(":"), spec.hasSuffix(":")) {
            case (true, true): return .center
            case (false, true): return .right
            default: return .left
            }
        }

        var rowIndexes = [headerIndex]
        var next = headerIndex + 2
        while next < lines.count {
            let candidate = source.substring(with: lines[next])
            guard candidate.contains("|"), !candidate.trimmingCharacters(in: .whitespaces).isEmpty else { break }
            rowIndexes.append(next)
            next += 1
        }

        struct Row {
            let range: NSRange
            let cells: [NSRange]
            let pipes: [Int]
            let inline: [Token]
            let visible: [Int]
            let markers: [NSRange]
        }
        let columnCount = headerCells.count
        var widths = [Int](repeating: 0, count: columnCount)
        var rows: [Row] = []
        for rowIndex in rowIndexes {
            let range = lines[rowIndex]
            let line = source.substring(with: range)
            let local = NSRange(location: 0, length: (line as NSString).length)
            let cells = cellRanges(in: line).map { NSRange(location: range.location + $0.location, length: $0.length) }
            let pipes = pipe.matches(in: line, range: local).map { range.location + $0.range.location }
            let inline = inlineTokens(in: line, offset: range.location, from: 0, definitions: definitions)
            let hiddenRanges = inline.flatMap(\.markers)
            let visible = cells.map { cell in cell.length - hiddenRanges.reduce(0) { $0 + NSIntersectionRange($1, cell).length } }
            var markers: [NSRange] = []
            let text = line as NSString
            let leading = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let trailing = line.reversed().prefix(while: { $0 == " " || $0 == "\t" }).count
            if leading < text.length, text.character(at: leading) == 0x7C {
                markers.append(NSRange(location: range.location + leading, length: 1))
            }
            let last = text.length - 1 - trailing
            if last > leading, text.character(at: last) == 0x7C {
                markers.append(NSRange(location: range.location + last, length: 1))
            }
            for (column, width) in visible.prefix(columnCount).enumerated() {
                widths[column] = max(widths[column], width)
            }
            rows.append(Row(range: range, cells: cells, pipes: pipes, inline: inline, visible: visible, markers: markers))
        }

        var tokens: [Token] = []
        for (position, row) in rows.enumerated() {
            let cells = row.cells.prefix(columnCount).enumerated().map { column, cell in
                TableCell(range: cell, visibleWidth: row.visible[column], columnWidth: widths[column], alignment: alignments[column])
            }
            tokens.append(Token(range: row.range, kind: .tableRow(cells: cells, isHeader: position == 0, pipes: row.pipes), markers: row.markers))
            tokens += row.inline
            if position == 0 {
                tokens.append(Token(range: delimiterRange, kind: .tableDelimiter, markers: [delimiterRange]))
            }
        }
        return TableParse(tokens: tokens, nextLine: next)
    }

    /// The text between pipes, in line coordinates; a leading or trailing pipe adds no empty cell,
    /// and `\|` stays inside its cell.
    private static func cellRanges(in line: String) -> [NSRange] {
        let text = line as NSString
        let pipes = pipe.matches(in: line, range: NSRange(location: 0, length: text.length)).map(\.range.location)
        let boundaries = [-1] + pipes + [text.length]
        var ranges: [NSRange] = []
        for position in 0..<(boundaries.count - 1) {
            let start = boundaries[position] + 1
            ranges.append(NSRange(location: start, length: boundaries[position + 1] - start))
        }
        let leading = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        if let first = pipes.first, first == leading {
            ranges.removeFirst()
        }
        let trailing = line.reversed().prefix(while: { $0 == " " || $0 == "\t" }).count
        if let last = pipes.last, last == text.length - 1 - trailing, !ranges.isEmpty, pipes.count > (pipes.first == leading ? 1 : 0) {
            ranges.removeLast()
        }
        return ranges
    }

    // MARK: - Inline

    /// Inline constructs of `line` from `start` on, in document order, ranges shifted by `offset`.
    private static func inlineTokens(in line: String, offset: Int, from start: Int, definitions: [String: String]) -> [Token] {
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
        // Every construct needs a character most lines lack; a pass whose character is missing cannot
        // match and is skipped (the regexes ran on every line: two thirds of tokenizing, PERF-2).
        let units = line.utf16
        let hasBacktick = units.contains(0x60), hasBackslash = units.contains(0x5C), hasDollar = units.contains(0x24)
        let hasAngle = units.contains(0x3C), hasBracket = units.contains(0x5B), hasTilde = units.contains(0x7E)
        let hasEmphasis = units.contains(0x2A) || units.contains(0x5F)

        for span in hasBacktick ? codeSpans(in: line as NSString, region: region) : [] {
            tokens.append(Token(range: shifted(span.range), kind: .inlineCode, markers: edges(span.range, open: span.run, close: span.run)))
            mask(span.range)
        }
        for match in hasBackslash ? escape.matches(in: scratch as String, range: region) : [] {
            tokens.append(Token(range: shifted(match.range), kind: .escape, markers: [NSRange(location: offset + match.range.location, length: 1)]))
            mask(match.range)
        }
        for match in hasDollar ? displayMath.matches(in: scratch as String, range: region) : [] {
            tokens.append(Token(range: shifted(match.range), kind: .math(display: true), markers: edges(match.range, open: 2, close: 2)))
            mask(match.range)
        }
        for match in hasDollar ? inlineMath.matches(in: scratch as String, range: region) : [] {
            tokens.append(Token(range: shifted(match.range), kind: .math(display: false), markers: edges(match.range, open: 1, close: 1)))
            mask(match.range)
        }
        for match in hasAngle ? autolink.matches(in: scratch as String, range: region) : [] {
            let inner = NSRange(location: match.range.location + 1, length: match.range.length - 2)
            tokens.append(Token(range: shifted(match.range), kind: .autolink(destination: scratch.substring(with: inner)), markers: edges(match.range, open: 1, close: 1)))
            mask(match.range)
        }
        // Inline links and images, read the way CommonMark reads them (`inlineLink`): images first, so a
        // badge (a link around an image) keeps both, and before the HTML pass, which took a `<…>`
        // destination for a tag. Only the markers are masked; the text still parses.
        for isImage in hasBracket ? [true, false] : [] {
            var index = region.location
            while index < NSMaxRange(region) {
                let start = isImage ? index + 1 : index
                guard start < NSMaxRange(region), scratch.character(at: start) == 0x5B, // "["
                      !isImage || scratch.character(at: index) == 0x21, // "!"
                      let link = inlineLink(in: scratch, bracket: start, end: NSMaxRange(region)) else {
                    index += 1
                    continue
                }
                let opening = NSRange(location: index, length: start + 1 - index)
                let closing = NSRange(location: link.textEnd, length: link.end - link.textEnd)
                let kind: Token.Kind = isImage ? .image(destination: link.destination) : .link(destination: link.destination)
                tokens.append(Token(range: shifted(NSRange(location: index, length: link.end - index)), kind: kind,
                                    markers: [shifted(opening), shifted(closing)]))
                mask(opening)
                mask(closing)
                index = start + 1
            }
        }
        if hasAngle { tokens += htmlTokens(in: scratch, region: region, offset: offset, mask: mask) }
        for match in hasBracket ? footnoteReference.matches(in: scratch as String, range: region) : [] {
            tokens.append(Token(range: shifted(match.range), kind: .footnoteReference, markers: edges(match.range, open: 2, close: 1)))
            mask(match.range)
        }
        for match in hasBracket ? referenceLink.matches(in: scratch as String, range: region) : [] {
            let text = match.range(at: 2)
            let explicit = match.range(at: 3)
            let label = explicit.location != NSNotFound && explicit.length > 0 ? explicit : text
            guard let destination = definitions[normalized(label: scratch.substring(with: label))] else { continue }
            let isImage = match.range(at: 1).length == 1
            let open = NSRange(location: offset + match.range.location, length: isImage ? 2 : 1)
            let close = NSRange(location: offset + NSMaxRange(text), length: NSMaxRange(match.range) - NSMaxRange(text))
            tokens.append(Token(range: shifted(match.range), kind: isImage ? .image(destination: destination) : .link(destination: destination), markers: [open, close]))
            mask(match.range)
        }
        for match in hasEmphasis ? boldItalic.matches(in: scratch as String, range: region) : [] {
            // `***text***`: strong over the whole with three-character markers, emphasis on the text itself.
            tokens.append(Token(range: shifted(match.range), kind: .strong, markers: edges(match.range, open: 3, close: 3)))
            tokens.append(Token(range: shifted(NSRange(location: match.range.location + 3, length: match.range.length - 6)), kind: .emphasis, markers: []))
            mask(match.range)
        }
        for match in hasEmphasis ? strong.matches(in: scratch as String, range: region) : [] {
            tokens.append(Token(range: shifted(match.range), kind: .strong, markers: edges(match.range, open: 2, close: 2)))
            mask(match.range)
        }
        for match in hasEmphasis ? emphasis.matches(in: scratch as String, range: region) : [] {
            tokens.append(Token(range: shifted(match.range), kind: .emphasis, markers: edges(match.range, open: 1, close: 1)))
        }
        for match in hasTilde ? strikethrough.matches(in: scratch as String, range: region) : [] {
            tokens.append(Token(range: shifted(match.range), kind: .strikethrough, markers: edges(match.range, open: 2, close: 2)))
        }
        return tokens.sorted { $0.range.location < $1.range.location }
    }

    /// Code spans as CommonMark reads them: a run of backticks closes at the next run of the same length,
    /// and shorter or longer runs between are code; a run without its match is literal, and so is a
    /// backtick after a backslash (BUG-23: runs of different lengths paired, so `` `ls` `` showed " ls ").
    private static func codeSpans(in line: NSString, region: NSRange) -> [(range: NSRange, run: Int)] {
        var spans: [(range: NSRange, run: Int)] = []
        let end = NSMaxRange(region)
        func run(at index: Int) -> Int {
            var length = 0
            while index + length < end, line.character(at: index + length) == 0x60 { length += 1 }
            return length
        }
        var index = region.location
        while index < end {
            guard line.character(at: index) == 0x60 else {
                // An escaped backtick is literal.
                index += line.character(at: index) == 0x5C && index + 1 < end ? 2 : 1
                continue
            }
            let length = run(at: index)
            var search = index + length
            var close: Int?
            while search < end {
                guard line.character(at: search) == 0x60 else {
                    search += 1
                    continue
                }
                let candidate = run(at: search)
                if candidate == length {
                    close = search
                    break
                }
                search += candidate
            }
            if let close {
                spans.append((NSRange(location: index, length: close + length - index), length))
                index = close + length
            } else {
                index += length
            }
        }
        return spans
    }

    /// The inline link or image whose text opens at `start` (its `[`, after any `!`), read as CommonMark
    /// reads it: text in balanced brackets that holds no other link, `(`, a destination either in `<…>`
    /// (spaces allowed) or as a run with balanced parentheses, an optional title after whitespace in
    /// `"…"`, `'…'` or `(…)`, and `)`. `textEnd` is the text's `]`, `end` just past the `)`; nil when a
    /// part is missing (`[a](/my uri)` is no link, as on the page).
    private static func inlineLink(in text: NSString, bracket start: Int, end limit: Int) -> (textEnd: Int, destination: String, end: Int)? {
        var depth = 0
        var index = start
        var textEnd: Int?
        while index < limit {
            let unit = text.character(at: index)
            if unit == 0x5B {
                depth += 1
            } else if unit == 0x5D {
                depth -= 1
                if depth == 0 {
                    textEnd = index
                    break
                }
            }
            index += 1
        }
        guard let textEnd, textEnd + 1 < limit, text.character(at: textEnd + 1) == 0x28, // "("
              !text.substring(with: NSRange(location: start + 1, length: textEnd - start - 1)).contains("](") else { return nil }
        index = textEnd + 2
        func skipSpaces() {
            while index < limit, [0x20, 0x09].contains(text.character(at: index)) { index += 1 }
        }
        skipSpaces()
        let destination: String
        if index < limit, text.character(at: index) == 0x3C { // "<"
            let open = index + 1
            index = open
            while index < limit, text.character(at: index) != 0x3E { // ">"
                if text.character(at: index) == 0x3C { return nil }
                index += 1
            }
            guard index < limit else { return nil }
            destination = text.substring(with: NSRange(location: open, length: index - open))
            index += 1
        } else {
            let begin = index
            var parentheses = 0
            while index < limit {
                let unit = text.character(at: index)
                if unit <= 0x20 { break }
                if unit == 0x28 {
                    parentheses += 1
                } else if unit == 0x29 {
                    if parentheses == 0 { break }
                    parentheses -= 1
                }
                index += 1
            }
            guard parentheses == 0 else { return nil }
            destination = text.substring(with: NSRange(location: begin, length: index - begin))
        }
        let afterDestination = index
        skipSpaces()
        let closers: [unichar: unichar] = [0x22: 0x22, 0x27: 0x27, 0x28: 0x29] // `"…"`, `'…'`, `(…)`
        if index > afterDestination, index < limit, let closer = closers[text.character(at: index)] {
            index += 1
            while index < limit, text.character(at: index) != closer { index += 1 }
            guard index < limit else { return nil }
            index += 1
            skipSpaces()
        }
        guard index < limit, text.character(at: index) == 0x29 else { return nil } // ")"
        return (textEnd, destination, index + 1)
    }

    /// Tags of `scratch` within `region`: comments, `<img>` as images, elements whose closing tag is
    /// on the same line, and every other tag on its own. Each tag is masked; content is not, so the
    /// Markdown inside an element still parses.
    private static func htmlTokens(in scratch: NSMutableString, region: NSRange, offset: Int, mask: (NSRange) -> Void) -> [Token] {
        var tokens: [Token] = []
        var open: [(name: String, range: NSRange, attributes: [String: String])] = []
        func lone(_ name: String?, _ attributes: [String: String], _ range: NSRange) -> Token {
            Token(range: NSRange(location: offset + range.location, length: range.length), kind: .html(element: name, attributes: attributes), markers: [NSRange(location: offset + range.location, length: range.length)])
        }
        for match in html.matches(in: scratch as String, range: region) {
            let range = match.range
            defer { mask(range) }
            guard match.range(at: 2).location != NSNotFound else {
                tokens.append(lone(nil, [:], range))
                continue
            }
            let name = scratch.substring(with: match.range(at: 2)).lowercased()
            let attributes = self.attributes(in: scratch.substring(with: match.range(at: 3)))
            let isClosing = match.range(at: 1).length == 1
            if isClosing {
                if let index = open.lastIndex(where: { $0.name == name }) {
                    let opener = open.remove(at: index)
                    let element = NSRange(location: offset + opener.range.location, length: NSMaxRange(range) - opener.range.location)
                    let markers = [NSRange(location: offset + opener.range.location, length: opener.range.length), NSRange(location: offset + range.location, length: range.length)]
                    tokens.append(Token(range: element, kind: .html(element: name, attributes: opener.attributes), markers: markers))
                } else {
                    tokens.append(lone(name, [:], range))
                }
            } else if name == "img", let source = attributes["src"], !source.isEmpty {
                tokens.append(Token(range: NSRange(location: offset + range.location, length: range.length), kind: .image(destination: source), markers: [NSRange(location: offset + range.location, length: range.length)]))
            } else if match.range(at: 4).length == 1 || voidElements.contains(name) {
                tokens.append(lone(name, attributes, range))
            } else {
                open.append((name, range, attributes))
            }
        }
        tokens += open.map { lone($0.name, $0.attributes, $0.range) }
        return tokens
    }

    private static func attributes(in text: String) -> [String: String] {
        var attributes: [String: String] = [:]
        let source = text as NSString
        for match in attribute.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let name = source.substring(with: match.range(at: 1)).lowercased()
            let value = (2...4).map { match.range(at: $0) }.first { $0.location != NSNotFound }
            attributes[name] = value.map { source.substring(with: $0) } ?? ""
        }
        return attributes
    }

    static func spans(from tokens: [Token]) -> [Span] {
        var spans: [Span] = []
        for token in tokens {
            switch token.kind {
            case .heading: spans.append(Span(range: token.range, kind: .heading))
            case .headingUnderline: spans.append(Span(range: token.range, kind: .rule))
            case .strong: spans.append(Span(range: token.range, kind: .strong))
            case .emphasis: spans.append(Span(range: token.range, kind: .emphasis))
            case .strikethrough: spans.append(Span(range: token.range, kind: .strikethrough))
            case .inlineCode: spans.append(Span(range: token.range, kind: .inlineCode))
            case .link, .image:
                // An `<img>` tag is one marker and colors like other tags.
                guard token.markers.count == 2 else {
                    spans += token.markers.map { Span(range: $0, kind: .html) }
                    continue
                }
                let close = token.markers[1]
                spans.append(Span(range: NSRange(location: token.range.location, length: close.location + 1 - token.range.location), kind: .link))
                spans.append(Span(range: NSRange(location: close.location + 1, length: close.length - 1), kind: .url))
            case .autolink: spans.append(Span(range: token.range, kind: .url))
            case .footnoteReference, .footnoteDefinition: spans.append(Span(range: token.range, kind: .link))
            case .html:
                for marker in token.markers { spans.append(Span(range: marker, kind: .html)) }
            case .linkDefinition: spans.append(Span(range: token.range, kind: .link))
            case .escape: break
            case .math, .mathFence: spans.append(Span(range: token.range, kind: .math))
            case .listItem: spans.append(Span(range: token.range, kind: .listMarker))
            case .quote: spans.append(Span(range: token.range, kind: .quote))
            case .callout:
                spans.append(Span(range: token.range, kind: .quote))
                if let marker = token.markers.last { spans.append(Span(range: marker, kind: .callout)) }
            case .rule: spans.append(Span(range: token.range, kind: .rule))
            case .fence, .code: spans.append(Span(range: token.range, kind: .codeBlock))
            case .frontMatter: spans.append(Span(range: token.range, kind: .frontMatter))
            case .tableRow(_, _, let pipes):
                spans += pipes.map { Span(range: NSRange(location: $0, length: 1), kind: .table) }
            case .tableDelimiter: spans.append(Span(range: token.range, kind: .table))
            }
        }
        return spans
    }
}
