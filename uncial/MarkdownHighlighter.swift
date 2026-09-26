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

    private static let fenceRun = regex(#"`{3,}|~{3,}"#)
    private static let rule = regex(#"^\s{0,3}([-*_])(\s*\1){2,}\s*$"#)
    private static let heading = regex(#"^\s{0,3}(#{1,6})(?:[ \t]+|$)"#)
    private static let setextUnderline = regex(#"^\s{0,3}(=+|-+)\s*$"#)
    private static let quote = regex(#"^(?:[ \t]{0,3}>[ \t]?)+"#)
    private static let listMarker = regex(#"^\s*([-+*]|\d{1,9}[.)])\s+(?:(\[[ xX]\])\s+)?"#)
    private static let footnoteDefinition = regex(#"^\[\^[^\]\s]+\]:"#)
    private static let tableDelimiter = regex(#"^\s{0,3}\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?\s*$"#)
    private static let pipe = regex(#"(?<!\\)\|"#)
    // Emphasis needs text right inside its markers (`* 3 *` is arithmetic) and no backslash before them.
    private static let boldItalic = regex(#"(?<![\w*\\])\*\*\*(?!\s)[^*\n]+(?<![\s\\])\*\*\*(?![\w*])"#)
    private static let strong = regex(#"(?<!\\)\*\*(?!\s)[^*\n]+(?<![\s\\])\*\*|(?<!\\)__(?!\s)[^_\n]+(?<![\s\\])__"#)
    private static let emphasis = regex(#"(?<![\w*\\])\*(?!\s)[^*\n]+(?<![\s\\])\*(?![\w*])|(?<![\w_\\])_(?!\s)[^_\n]+(?<![\s\\])_(?![\w_])"#)
    private static let strikethrough = regex(#"~~[^~\n]+~~"#)
    private static let footnoteReference = regex(#"\[\^[^\]\s]+\](?!:)"#)
    // cmark's raw HTML (scanners.re): a comment (`<!-->` and `<!--->` whole ones), a processing
    // instruction, a declaration, CDATA, or a tag whose attributes each follow whitespace and have a
    // valid name and value; a closing tag takes no attributes (checked where it is read).
    private static let html = regex(
        #"<!--(?:-?>|(?:[^\x00-]|-[^\x00-]|--[^\x00>])*-->)|<\?[\s\S]*?\?>|<![A-Z]+\s+[^>\x00]*>|<!\[CDATA\[[\s\S]*?\]\]>"#
            + #"|<(/?)([A-Za-z][A-Za-z0-9-]*)((?:\s+[A-Za-z_:][A-Za-z0-9_.:-]*(?:\s*=\s*(?:[^\s"'=<>`\x00]+|'[^'\x00]*'|"[^"\x00]*"))?)*)\s*(/?)>"#
    )
    /// Inside an HTML block the browser reads the tags: any attributes (quoted ones may hold `>`), and
    /// attributes on a closing tag too.
    private static let lenientHTML = regex(
        #"<!--(?:-?>|(?:[^\x00-]|-[^\x00-]|--[^\x00>])*-->)|<\?[\s\S]*?\?>|<![A-Za-z][^>]*>|<!\[CDATA\[[\s\S]*?\]\]>"#
            + #"|<(/?)([A-Za-z][A-Za-z0-9-]*)((?:\s(?:[^<>"']|"[^"]*"|'[^']*')*)?)(/?)>"#
    )
    /// cmark's autolinks: any scheme of 2 to 32 characters, or an email address.
    private static let autolinkURI = regex(#"<[A-Za-z][A-Za-z0-9.+-]{1,31}:[^\x00-\x20<>]*>"#)
    private static let autolinkEmail = regex(
        #"<[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*>"#
    )
    /// Tags GFM's tag filter shows as text (`&lt;script>`).
    private static let filteredTags: Set<String> = ["title", "textarea", "style", "xmp", "iframe", "noembed", "noframes", "script", "plaintext"]
    private static let attribute = regex(#"([A-Za-z_:][-A-Za-z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?"#)
    /// Tags that never have content: a lone `<br>` needs no `</br>`.
    private static let voidElements: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
    private static let referenceLink = regex(#"(!?)\[([^\[\]\n]+)\](?:\[([^\[\]\n]*)\])?"#)
    private static let mathFence = regex(#"^\s{0,3}\$\$\s*$"#)

    static func spans(in text: String) -> [Span] {
        spans(from: tokens(in: text))
    }

    static func tokens(in text: String) -> [Token] {
        let source = text as NSString
        let lines = lineRanges(of: source)
        var tokens: [Token] = []
        var inMathBlock = false
        var index = 0
        // cmark decides which lines are code or HTML (fenced code in a list item, indented code, HTML
        // blocks: the line regexes knew none of them; REF-3) and which are definitions (BUG-28). Its
        // body starts after the front matter.
        let bodyStart = FrontMatter.bodyLineOffset(of: text)
        let blocks = MarkdownBlocks(bodyStart > 0 ? FrontMatter.split(text).body : text)
        let definitions = References(blocks, bodyStart: bodyStart)
        let cmarkLines = cmarkLineNumbers(of: lines, in: source)

        while index < lines.count {
            let current = index
            index += 1
            let cmarkLine = cmarkLines[current]
            let contentRange = lines[current]
            let lineStart = contentRange.location
            let line = source.substring(with: contentRange)
            let whole = NSRange(location: 0, length: (line as NSString).length)
            func shifted(_ range: NSRange) -> NSRange {
                NSRange(location: lineStart + range.location, length: range.length)
            }

            // Front matter as the page takes it off: only when it closes, behind a byte order mark too
            // (an unclosed `---` made the whole note front matter, BUG-28).
            if cmarkLine < bodyStart {
                tokens.append(Token(range: contentRange, kind: .frontMatter, markers: []))
                continue
            }
            // Code and HTML as cmark reads them (CommonMark's fence rules included: ```npm install``` is
            // inline code, ```js inside a block is content). Blocks inside a quote are left to the quote
            // path, which draws the bars and callouts.
            if cmarkLine >= bodyStart, let block = blocks.kind(ofLine: cmarkLine - bodyStart) {
                switch block {
                case .fenceOpening, .fenceClosing:
                    let marker = fenceRun.firstMatch(in: line, range: whole).map { [shifted($0.range)] } ?? []
                    tokens.append(Token(range: contentRange, kind: .fence, markers: marker))
                case .fencedCode, .indentedCode:
                    tokens.append(Token(range: contentRange, kind: .code, markers: []))
                case .html:
                    // The page shows an HTML block's text as written: only its tags are read.
                    let scratch = NSMutableString(string: line)
                    let tags = lenientHTML.matches(in: line, range: whole).filter { isTag($0, in: scratch, strict: false) }
                    tokens += htmlTokens(for: tags, in: scratch, offset: lineStart) { range in
                        scratch.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
                    }
                }
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
                if definitions.lines.contains(cmarkLine) {
                    tokens.append(Token(range: shifted(NSRange(location: match.range.length, length: whole.length - match.range.length)), kind: .linkDefinition, markers: []))
                } else {
                    tokens += inlineTokens(in: line, offset: lineStart, from: match.range.length, definitions: definitions)
                }
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
            if definitions.lines.contains(cmarkLine) {
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

    /// What the document defines, as cmark reads it: link destinations by normalized label (the first
    /// definition of a label wins), the lines the definitions take, and the footnotes the page shows.
    /// A line that only looks like a definition (in code, inside a paragraph, with more than a title
    /// after its destination) defined a link before, and an undefined `[^note]` was a footnote (BUG-28).
    private struct References {
        var links: [String: String] = [:]
        var lines: Set<Int> = []
        var footnotes: Set<String> = []

        init(_ blocks: MarkdownBlocks, bodyStart: Int) {
            for definition in blocks.linkDefinitions {
                let label = MarkdownHighlighter.normalized(label: definition.label)
                if links[label] == nil { links[label] = definition.destination }
                lines.formUnion(definition.lines.map { $0 + bodyStart })
            }
            footnotes = Set(blocks.footnoteLabels.map(MarkdownHighlighter.normalized(label:)))
        }
    }

    /// A label as cmark matches it: case-folded (`ẞ` is `SS`), inner whitespace collapsed.
    private static func normalized(label: String) -> String {
        label.folding(options: .caseInsensitive, locale: nil).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The cmark line each of `lines` belongs to: cmark breaks lines at `\n`, `\r\n` and `\r` only, NSString
    /// also at U+2028, U+2029 and U+0085, and one of those shifted every block below it.
    private static func cmarkLineNumbers(of lines: [NSRange], in source: NSString) -> [Int] {
        var numbers: [Int] = []
        numbers.reserveCapacity(lines.count)
        var number = 0
        for line in lines {
            if line.location > 0, [0x0A, 0x0D].contains(source.character(at: line.location - 1)) { number += 1 }
            numbers.append(number)
        }
        return numbers
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
    private static func tableTokens(startingAt headerIndex: Int, lines: [NSRange], source: NSString, definitions: References) -> TableParse? {
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
    private static func inlineTokens(in line: String, offset: Int, from start: Int, definitions: References) -> [Token] {
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

        // Math first, as the page's `MathSource` takes it out before cmark reads the line: TeX's `\{` and
        // `\,` are no escapes (BUG-28).
        for span in hasDollar ? mathSpans(in: line as NSString, region: region) : [] {
            let edge = span.display ? 2 : 1
            tokens.append(Token(range: shifted(span.range), kind: .math(display: span.display), markers: edges(span.range, open: edge, close: edge)))
            mask(span.range)
        }
        // Then cmark's atoms, whichever starts first.
        if hasBacktick || hasBackslash || hasAngle {
            var tags: [NSTextCheckingResult] = []
            for atom in atoms(in: scratch, region: region) {
                switch atom {
                case .escape(let range):
                    tokens.append(Token(range: shifted(range), kind: .escape, markers: [NSRange(location: offset + range.location, length: 1)]))
                    mask(range)
                case .code(let range, let run):
                    tokens.append(Token(range: shifted(range), kind: .inlineCode, markers: edges(range, open: run, close: run)))
                    mask(range)
                case .autolink(let range, let destination):
                    tokens.append(Token(range: shifted(range), kind: .autolink(destination: destination), markers: edges(range, open: 1, close: 1)))
                    mask(range)
                case .tag(let match):
                    tags.append(match)
                }
            }
            tokens += htmlTokens(for: tags, in: scratch, offset: offset, mask: mask)
        }
        // Inline links and images, read the way CommonMark reads them (`inlineLink`): images first, so a
        // badge (a link around an image) keeps both. Only the markers are masked; the text still parses.
        for isImage in hasBracket ? [true, false] : [] {
            var index = region.location
            while index < NSMaxRange(region) {
                let start = isImage ? index + 1 : index
                guard start < NSMaxRange(region), scratch.character(at: start) == 0x5B, // "["
                      !isImage || scratch.character(at: index) == 0x21, // "!"
                      let link = inlineLink(in: scratch, source: line as NSString, bracket: start, end: NSMaxRange(region)) else {
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
        for match in hasBracket ? footnoteReference.matches(in: scratch as String, range: region) : [] {
            let label = scratch.substring(with: NSRange(location: match.range.location + 2, length: match.range.length - 3))
            guard definitions.footnotes.contains(normalized(label: label)) else { continue }
            tokens.append(Token(range: shifted(match.range), kind: .footnoteReference, markers: edges(match.range, open: 2, close: 1)))
            mask(match.range)
        }
        // Reference links, left to right: brackets that make no link (an undefined label, or a link's text
        // holding a link, `[a [b](c)][ref]`) leave the brackets after them to be read (BUG-28). Only the
        // markers are masked, so the text still parses.
        var search = region.location
        while hasBracket, search < NSMaxRange(region),
              let match = referenceLink.firstMatch(in: scratch as String, range: NSRange(location: search, length: NSMaxRange(region) - search)) {
            let text = match.range(at: 2)
            let explicit = match.range(at: 3)
            let label = explicit.location != NSNotFound && explicit.length > 0 ? explicit : text
            let isImage = match.range(at: 1).length == 1
            let holdsLink = !isImage && tokens.contains { token in
                guard case .link = token.kind else { return false }
                return NSLocationInRange(token.range.location, shifted(text))
            }
            guard !holdsLink, let destination = definitions.links[normalized(label: scratch.substring(with: label))] else {
                search = match.range.location + 1
                continue
            }
            let open = NSRange(location: match.range.location, length: isImage ? 2 : 1)
            let close = NSRange(location: NSMaxRange(text), length: NSMaxRange(match.range) - NSMaxRange(text))
            tokens.append(Token(range: shifted(match.range), kind: isImage ? .image(destination: destination) : .link(destination: destination),
                                markers: [shifted(open), shifted(close)]))
            mask(open)
            mask(close)
            search = NSMaxRange(match.range)
        }
        // The regexes propose; CommonMark decides: each run must be able to open or close (flanking, and
        // `_` never inside a word), and no pair may join a delimiter outside a link's text to one inside.
        let original = line as NSString
        let linkTexts: [NSRange] = tokens.compactMap { token in
            switch token.kind {
            case .link, .image:
                guard token.markers.count == 2 else { return nil }
                let start = NSMaxRange(token.markers[0]) - offset
                return NSRange(location: start, length: max(0, token.markers[1].location - offset - start))
            default:
                return nil
            }
        }
        func pairs(_ match: NSRange, run: Int) -> Bool {
            let open = NSRange(location: match.location, length: run)
            let close = NSRange(location: NSMaxRange(match) - run, length: run)
            guard canOpen(open, in: original), canClose(close, in: original) else { return false }
            return !linkTexts.contains { NSLocationInRange(open.location, $0) != NSLocationInRange(close.location, $0) }
        }
        for match in hasEmphasis ? boldItalic.matches(in: scratch as String, range: region) : [] where pairs(match.range, run: 3) {
            // `***text***`: strong over the whole with three-character markers, emphasis on the text itself.
            tokens.append(Token(range: shifted(match.range), kind: .strong, markers: edges(match.range, open: 3, close: 3)))
            tokens.append(Token(range: shifted(NSRange(location: match.range.location + 3, length: match.range.length - 6)), kind: .emphasis, markers: []))
            mask(match.range)
        }
        for match in hasEmphasis ? strong.matches(in: scratch as String, range: region) : [] where pairs(match.range, run: 2) {
            tokens.append(Token(range: shifted(match.range), kind: .strong, markers: edges(match.range, open: 2, close: 2)))
            mask(match.range)
        }
        for match in hasEmphasis ? emphasis.matches(in: scratch as String, range: region) : [] where pairs(match.range, run: 1) {
            tokens.append(Token(range: shifted(match.range), kind: .emphasis, markers: edges(match.range, open: 1, close: 1)))
        }
        for match in hasTilde ? strikethrough.matches(in: scratch as String, range: region) : [] where pairs(match.range, run: 2) {
            tokens.append(Token(range: shifted(match.range), kind: .strikethrough, markers: edges(match.range, open: 2, close: 2)))
        }
        return tokens.sorted { $0.range.location < $1.range.location }
    }

    /// Whether the delimiter run at `run` can open emphasis: left-flanking, and a `_` run not also
    /// right-flanking unless punctuation comes before it (so never inside a word).
    private static func canOpen(_ run: NSRange, in line: NSString) -> Bool {
        let (left, right) = flanking(run, in: line)
        guard left else { return false }
        guard line.character(at: run.location) == 0x5F else { return true } // "_"
        return !right || character(before: run, in: line).map(isPunctuation) == true
    }

    /// Whether the run at `run` can close emphasis: right-flanking, and a `_` run not also left-flanking
    /// unless punctuation comes after it.
    private static func canClose(_ run: NSRange, in line: NSString) -> Bool {
        let (left, right) = flanking(run, in: line)
        guard right else { return false }
        guard line.character(at: run.location) == 0x5F else { return true }
        return !left || character(after: run, in: line).map(isPunctuation) == true
    }

    /// CommonMark's flanking: a left-flanking run is not followed by whitespace, and not followed by
    /// punctuation unless whitespace or punctuation precedes it; right-flanking mirrors that. The start
    /// and end of the line count as whitespace.
    private static func flanking(_ run: NSRange, in line: NSString) -> (left: Bool, right: Bool) {
        let previous = character(before: run, in: line)
        let next = character(after: run, in: line)
        let previousSpace = previous.map(\.isWhitespace) ?? true
        let nextSpace = next.map(\.isWhitespace) ?? true
        let previousPunctuation = previous.map(isPunctuation) ?? false
        let nextPunctuation = next.map(isPunctuation) ?? false
        let left = !nextSpace && (!nextPunctuation || previousSpace || previousPunctuation)
        let right = !previousSpace && (!previousPunctuation || nextSpace || nextPunctuation)
        return (left, right)
    }

    private static func character(before run: NSRange, in line: NSString) -> Character? {
        guard run.location > 0 else { return nil }
        return Character(line.substring(with: line.rangeOfComposedCharacterSequence(at: run.location - 1)))
    }

    private static func character(after run: NSRange, in line: NSString) -> Character? {
        guard NSMaxRange(run) < line.length else { return nil }
        return Character(line.substring(with: line.rangeOfComposedCharacterSequence(at: NSMaxRange(run))))
    }

    /// CommonMark's punctuation: Unicode's punctuation and symbols (ASCII `$`, `+`, `<`, `|`, … are symbols).
    private static func isPunctuation(_ character: Character) -> Bool {
        character.isPunctuation || character.isSymbol
    }

    private enum Atom {
        case escape(NSRange)
        case code(NSRange, run: Int)
        case autolink(NSRange, destination: String)
        case tag(NSTextCheckingResult)
    }

    /// cmark's atoms of `line` in `region` as its inline parser meets them, left to right: a backslash
    /// escape, a code span (a backtick run up to the next run of the same length), an autolink or a raw
    /// HTML tag, whichever starts first, none inside another. So `<a href="`">` is a tag and `` `<b>` ``
    /// code, escapes stay as written in autolinks and tags, and a tag in a link's text hides the `]` in
    /// it (BUG-28). An inline link's tail after `](` is the link's: a `<…>` destination is neither an
    /// autolink nor a tag.
    private static func atoms(in line: NSString, region: NSRange) -> [Atom] {
        var atoms: [Atom] = []
        let end = NSMaxRange(region)
        var index = region.location
        while index < end {
            let unit = line.character(at: index)
            if unit == 0x5C, index + 1 < end, isASCIIPunctuation(line.character(at: index + 1)) { // "\"
                atoms.append(.escape(NSRange(location: index, length: 2)))
                index += 2
            } else if unit == 0x60 { // "`"
                let length = backtickRun(in: line, at: index, end: end)
                if let close = closingBacktickRun(in: line, from: index + length, length: length, end: end) {
                    atoms.append(.code(NSRange(location: index, length: close + length - index), run: length))
                    index = close + length
                } else {
                    index += length
                }
            } else if unit == 0x3C, let atom = angleAtom(in: line, at: index, end: end) { // "<"
                atoms.append(atom.atom)
                index = atom.end
            } else if unit == 0x5D, index + 1 < end, line.character(at: index + 1) == 0x28, // "]("
                      let tail = linkTail(in: line, open: index + 1, end: end) {
                index = tail.end
            } else {
                index += 1
            }
        }
        return atoms
    }

    /// The autolink or tag at `index` (a `<`), autolinks first as cmark tries them.
    private static func angleAtom(in line: NSString, at index: Int, end: Int) -> (atom: Atom, end: Int)? {
        let rest = NSRange(location: index, length: end - index)
        let text = line as String
        if let match = autolinkURI.firstMatch(in: text, options: .anchored, range: rest) {
            let inner = line.substring(with: NSRange(location: index + 1, length: match.range.length - 2))
            return (.autolink(match.range, destination: inner), NSMaxRange(match.range))
        }
        if let match = autolinkEmail.firstMatch(in: text, options: .anchored, range: rest) {
            let inner = line.substring(with: NSRange(location: index + 1, length: match.range.length - 2))
            return (.autolink(match.range, destination: "mailto:" + inner), NSMaxRange(match.range))
        }
        if let match = html.firstMatch(in: text, options: .anchored, range: rest), isTag(match, in: line, strict: true) {
            return (.tag(match), NSMaxRange(match.range))
        }
        return nil
    }

    /// Whether a match of `html` or `lenientHTML` is a tag the page keeps as HTML: not one GFM's tag
    /// filter shows as text, and, read strictly as cmark does, no closing tag with attributes.
    private static func isTag(_ match: NSTextCheckingResult, in line: NSString, strict: Bool) -> Bool {
        guard match.range(at: 2).location != NSNotFound else { return true } // a comment, declaration…
        let isClosing = match.range(at: 1).length == 1
        if strict, isClosing, match.range(at: 3).length > 0 || match.range(at: 4).length > 0 { return false }
        return !filteredTags.contains(line.substring(with: match.range(at: 2)).lowercased())
    }

    private static func backtickRun(in line: NSString, at index: Int, end: Int) -> Int {
        var length = 0
        while index + length < end, line.character(at: index + length) == 0x60 { length += 1 }
        return length
    }

    /// Where the next backtick run of exactly `length` starts from `start`, closing a code span: shorter
    /// or longer runs between are code (BUG-23: runs of different lengths paired, so `` `ls` `` showed " ls ").
    private static func closingBacktickRun(in line: NSString, from start: Int, length: Int, end: Int) -> Int? {
        var index = start
        while index < end {
            guard line.character(at: index) == 0x60 else {
                index += 1
                continue
            }
            let run = backtickRun(in: line, at: index, end: end)
            if run == length { return index }
            index += run
        }
        return nil
    }

    private static func isASCIIPunctuation(_ unit: unichar) -> Bool {
        (0x21...0x2F).contains(unit) || (0x3A...0x40).contains(unit) || (0x5B...0x60).contains(unit) || (0x7B...0x7E).contains(unit)
    }

    /// The formulas of `line` in `region` as the page's `MathSource` finds them before cmark reads the
    /// line, left to right: a backslash hides the character after it, code spans are skipped, `$$…$$`
    /// closes on the line (no backtick inside, no backslash before it), and `$…$` follows `MathRenderer`'s
    /// rules: no word character, `$` or backslash before the opening dollar, no space or `$` right inside
    /// it, the first `$` after it closes (not after a space or a backslash, not before a digit or a `$`),
    /// no backtick inside.
    private static func mathSpans(in line: NSString, region: NSRange) -> [(range: NSRange, display: Bool)] {
        var spans: [(range: NSRange, display: Bool)] = []
        let end = NSMaxRange(region)
        func scalar(at index: Int) -> Unicode.Scalar? {
            guard index >= 0, index < line.length else { return nil }
            let unit = line.character(at: index)
            if UTF16.isLeadSurrogate(unit), index + 1 < line.length, UTF16.isTrailSurrogate(line.character(at: index + 1)) {
                return Unicode.Scalar(0x10000 + (UInt32(unit) - 0xD800) << 10 + (UInt32(line.character(at: index + 1)) - 0xDC00))
            }
            return Unicode.Scalar(unit)
        }
        func scalar(before index: Int) -> Unicode.Scalar? {
            guard index > 0 else { return nil }
            let unit = line.character(at: index - 1)
            return UTF16.isTrailSurrogate(unit) && index >= 2 ? scalar(at: index - 2) : Unicode.Scalar(unit)
        }
        func hasBacktick(_ range: Range<Int>) -> Bool {
            range.contains { line.character(at: $0) == 0x60 }
        }
        var index = region.location
        while index < end {
            let unit = line.character(at: index)
            if unit == 0x5C { // "\"
                index += 2
            } else if unit == 0x60 { // "`"
                let length = backtickRun(in: line, at: index, end: end)
                index = closingBacktickRun(in: line, from: index + length, length: length, end: end).map { $0 + length } ?? index + length
            } else if unit == 0x24, index + 1 < end, line.character(at: index + 1) == 0x24 { // "$$"
                var close = index + 3
                while close + 1 < end, !(line.character(at: close) == 0x24 && line.character(at: close + 1) == 0x24) { close += 1 }
                guard scalar(before: index) != "\\", close + 1 < end, !hasBacktick((index + 2)..<close) else {
                    index += 2
                    continue
                }
                spans.append((NSRange(location: index, length: close + 2 - index), true))
                index = close + 2
            } else if unit == 0x24, !opensNoMath(scalar(before: index)), let close = inlineMathClose(in: line, open: index, end: end, scalar: scalar(at:)),
                      !hasBacktick((index + 1)..<close) {
                spans.append((NSRange(location: index, length: close + 1 - index), false))
                index = close + 1
            } else {
                index += 1
            }
        }
        return spans
    }

    /// No inline math opens after a word character, a `$` or a backslash.
    private static func opensNoMath(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return scalar == "$" || scalar == "\\" || scalar == "_" || scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }

    /// The closing dollar of inline math opening at `open`: the first one after it, when the math is
    /// not blank at either end, not closed after a backslash and not followed by a digit or a dollar.
    private static func inlineMathClose(in line: NSString, open: Int, end: Int, scalar: (Int) -> Unicode.Scalar?) -> Int? {
        let first = open + 1
        guard first < end, let head = scalar(first), !head.properties.isWhitespace, head != "$" else { return nil }
        var close = first
        while close < end, line.character(at: close) != 0x24 { close += 1 }
        guard close < end else { return nil }
        let before = UTF16.isTrailSurrogate(line.character(at: close - 1)) && close - 2 >= first ? scalar(close - 2) : scalar(close - 1)
        guard let last = before, !last.properties.isWhitespace, last != "\\" else { return nil }
        if let next = scalar(close + 1), close + 1 < end, next == "$" || next.properties.numericType != nil { return nil }
        return close
    }

    /// The inline link or image whose text opens at `start` (its `[`, after any `!`), read as CommonMark
    /// reads it: text in balanced brackets that holds no other link, `(`, a destination either in `<…>`
    /// (spaces allowed) or as a run with balanced parentheses, an optional title after whitespace in
    /// `"…"`, `'…'` or `(…)`, and `)`. `textEnd` is the text's `]`, `end` just past the `)`; nil when a
    /// part is missing (`[a](/my uri)` is no link, as on the page).
    private static func inlineLink(in text: NSString, source: NSString, bracket start: Int, end limit: Int) -> (textEnd: Int, destination: String, end: Int)? {
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
        guard let tail = linkTail(in: source, open: textEnd + 1, end: limit) else { return nil }
        return (textEnd, tail.destination, tail.end)
    }

    /// An inline link's tail from its `(` at `open`, read as written (a tag or code span inside is the
    /// tail's text): the destination and just past the `)`. A backslash escapes what follows.
    private static func linkTail(in text: NSString, open: Int, end limit: Int) -> (destination: String, end: Int)? {
        var index = open + 1
        func skipSpaces() {
            while index < limit, [0x20, 0x09].contains(text.character(at: index)) { index += 1 }
        }
        skipSpaces()
        let destination: String
        if index < limit, text.character(at: index) == 0x3C { // "<"
            let start = index + 1
            index = start
            while index < limit, text.character(at: index) != 0x3E { // ">"
                let unit = text.character(at: index)
                if unit == 0x3C { return nil }
                index += unit == 0x5C ? 2 : 1
            }
            guard index < limit else { return nil }
            destination = text.substring(with: NSRange(location: start, length: index - start))
            index += 1
        } else {
            let begin = index
            var parentheses = 0
            while index < limit {
                let unit = text.character(at: index)
                if unit <= 0x20 { break }
                if unit == 0x5C, index + 1 < limit, isASCIIPunctuation(text.character(at: index + 1)) {
                    index += 2
                    continue
                }
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
            while index < limit, text.character(at: index) != closer {
                index += text.character(at: index) == 0x5C && index + 1 < limit && isASCIIPunctuation(text.character(at: index + 1)) ? 2 : 1
            }
            guard index < limit else { return nil }
            index += 1
            skipSpaces()
        }
        guard index < limit, text.character(at: index) == 0x29 else { return nil } // ")"
        return (destination, index + 1)
    }

    /// Tokens for the `tags` of `scratch` (matches of `html` or `lenientHTML`, in order): comments,
    /// `<img>` as images, elements whose closing tag is on the same line, and every other tag on its
    /// own. Each tag is masked; content is not, so the Markdown inside an element still parses.
    private static func htmlTokens(for tags: [NSTextCheckingResult], in scratch: NSMutableString, offset: Int, mask: (NSRange) -> Void) -> [Token] {
        var tokens: [Token] = []
        var open: [(name: String, range: NSRange, attributes: [String: String])] = []
        func lone(_ name: String?, _ attributes: [String: String], _ range: NSRange) -> Token {
            Token(range: NSRange(location: offset + range.location, length: range.length), kind: .html(element: name, attributes: attributes), markers: [NSRange(location: offset + range.location, length: range.length)])
        }
        for match in tags {
            let range = match.range
            defer { mask(range) }
            guard match.range(at: 2).location != NSNotFound else {
                tokens.append(lone(nil, [:], range))
                continue
            }
            let name = scratch.substring(with: match.range(at: 2)).lowercased()
            let attributes = self.attributes(in: scratch.substring(with: match.range(at: 3)))
            if match.range(at: 1).length == 1 {
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
