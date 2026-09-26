import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// The lines of a Markdown body that cmark takes as they are: fenced code with its fences, indented
/// code, HTML blocks. The editor's tokenizer asks it so Live Preview hides no Markdown in text the
/// page shows as written: its line regexes knew no indented code, no fence indented inside a list
/// item and no HTML block (REF-3, 2026-09-26). It also holds the link reference definitions and the
/// footnotes as cmark reads them (BUG-28). Lines are the 0-based lines of the text given; front
/// matter, which the page removes first, is the caller's to leave out.
public struct MarkdownBlocks: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The line that opens a fenced code block.
        case fenceOpening
        /// A line inside a fenced code block.
        case fencedCode
        /// The fence that closes a block.
        case fenceClosing
        case indentedCode
        case html
    }

    /// A link reference definition: its label as written, its destination (without angle brackets)
    /// and the lines it takes.
    public struct LinkDefinition: Sendable, Equatable {
        public let label: String
        public let destination: String
        public let lines: ClosedRange<Int>

        public init(label: String, destination: String, lines: ClosedRange<Int>) {
            self.label = label
            self.destination = destination
            self.lines = lines
        }
    }

    private let kinds: [Int: Kind]
    /// The link reference definitions outside block quotes, in document order. cmark reads one only
    /// where a paragraph starts or right after another one, and drops a paragraph that holds nothing
    /// else, so they are read here from the start of every paragraph and of every run of lines no
    /// block covers.
    public let linkDefinitions: [LinkDefinition]
    /// The labels of the footnotes the page shows, as written: defined and referenced (cmark drops the
    /// others, and an undefined reference stays text).
    public let footnoteLabels: [String]

    public init(_ markdown: String) {
        var kinds: [Int: Kind] = [:]
        let lines = Self.lines(of: markdown)
        // Where definitions may start: paragraphs (and setext headings) with the byte column their
        // content starts at, and the lines no block covers.
        var paragraphs: [(lines: ClosedRange<Int>, column: Int)] = []
        var covered = [Bool](repeating: false, count: lines.count)
        var quoted = [Bool](repeating: false, count: lines.count)
        var footnoteLabels: [String] = []
        func mark(_ flags: inout [Bool], _ range: ClosedRange<Int>) {
            for line in range where line < flags.count { flags[line] = true }
        }
        GFMRenderer.withDocument(markdown, sourcePositions: true) { document, _ in
            guard let iterator = cmark_iter_new(document) else { return }
            defer { cmark_iter_free(iterator) }
            while true {
                let event = cmark_iter_next(iterator)
                guard event != CMARK_EVENT_DONE else { return }
                guard event == CMARK_EVENT_ENTER, let node = cmark_iter_get_node(iterator) else { continue }
                // cmark's lines are 1-based.
                let first = Int(cmark_node_get_start_line(node)) - 1
                let last = Int(cmark_node_get_end_line(node)) - 1
                guard first >= 0, last >= first else { continue }
                let type = cmark_node_get_type(node)
                switch type {
                case CMARK_NODE_DOCUMENT, CMARK_NODE_LIST:
                    continue
                case CMARK_NODE_BLOCK_QUOTE:
                    mark(&quoted, first...last)
                    continue
                case CMARK_NODE_ITEM:
                    // Only the marker's line: the item's paragraphs cover the rest.
                    mark(&covered, first...first)
                    continue
                case CMARK_NODE_FOOTNOTE_DEFINITION:
                    mark(&covered, first...first)
                    footnoteLabels.append(cmark_node_get_literal(node).map { String(cString: $0) } ?? "")
                    continue
                default:
                    if type.rawValue & UInt32(CMARK_NODE_TYPE_MASK) == UInt32(CMARK_NODE_TYPE_BLOCK) { mark(&covered, first...last) }
                }
                // Lines in a block quote carry its `>` prefixes: the editor reads those itself.
                guard !Self.isInQuote(node) else { continue }
                switch type {
                case CMARK_NODE_PARAGRAPH:
                    paragraphs.append((first...last, Int(cmark_node_get_start_column(node)) - 1))
                case CMARK_NODE_HEADING where last > first:
                    // A setext heading was a paragraph until its underline.
                    paragraphs.append((first...(last - 1), Int(cmark_node_get_start_column(node)) - 1))
                case CMARK_NODE_HTML_BLOCK:
                    for line in first...last { kinds[line] = .html }
                case CMARK_NODE_CODE_BLOCK:
                    var length: Int32 = 0, offset: Int32 = 0
                    var character: CChar = 0
                    guard cmark_node_get_fenced(node, &length, &offset, &character) != 0 else {
                        // cmark's range takes in the blank lines after the code.
                        var end = last
                        while end > first, end < lines.count, lines[end].allSatisfy(\.isWhitespace) { end -= 1 }
                        for line in first...end { kinds[line] = .indentedCode }
                        continue
                    }
                    kinds[first] = .fenceOpening
                    if last > first {
                        for line in (first + 1)...last { kinds[line] = .fencedCode }
                        // cmark keeps no "closed" flag: a closed block's content is one line short of its span.
                        let literal = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
                        let contentLines = literal.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
                        if last - first - 1 == contentLines { kinds[last] = .fenceClosing }
                    }
                default:
                    break
                }
            }
        }
        self.kinds = kinds
        self.footnoteLabels = footnoteLabels

        // A paragraph of definitions only is gone from the tree: its lines are the runs no block covers.
        var line = 0
        while line < lines.count {
            guard !covered[line], !quoted[line], !lines[line].allSatisfy(\.isWhitespace) else {
                line += 1
                continue
            }
            let start = line
            while line < lines.count, !covered[line], !quoted[line], !lines[line].allSatisfy(\.isWhitespace) { line += 1 }
            paragraphs.append((start...(line - 1), -1))
        }
        paragraphs.sort { $0.lines.lowerBound < $1.lines.lowerBound }
        var definitions: [LinkDefinition] = []
        for paragraph in paragraphs {
            definitions += Self.definitions(in: paragraph.lines, column: paragraph.column, of: lines)
        }
        self.linkDefinitions = definitions
    }

    /// The definitions at the start of a paragraph's content, read as cmark reads them: its lines
    /// without their indentation (the first from `column`, a byte offset, when there is one) and a
    /// line break after each.
    private static func definitions(in paragraph: ClosedRange<Int>, column: Int, of lines: [String]) -> [LinkDefinition] {
        guard paragraph.lowerBound < lines.count else { return [] }
        let first = Array(lines[paragraph.lowerBound].utf8)
        let start = column >= 0 ? min(column, first.count) : first.prefix { $0 == 0x20 || $0 == 0x09 }.count
        guard start < first.count, first[start] == 0x5B else { return [] } // "["
        var content = Array(first[start...])
        content.append(0x0A)
        for index in paragraph.dropFirst() where index < lines.count {
            content += lines[index].utf8.drop { $0 == 0x20 || $0 == 0x09 }
            content.append(0x0A)
        }
        var definitions: [LinkDefinition] = []
        var position = 0, line = paragraph.lowerBound
        while position < content.count, content[position] == 0x5B,
              let definition = ReferenceParser(content).definition(at: position) {
            // `[^note]:` at the start of a line opens a footnote, which ends the paragraph.
            if definition.label.hasPrefix("^"), !definition.label.contains(where: { $0 == " " || $0 == "\t" || $0 == "\n" }) { break }
            let breaks = content[position..<definition.end].reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
            definitions.append(LinkDefinition(label: definition.label, destination: definition.destination, lines: line...(line + max(breaks, 1) - 1)))
            line += breaks
            position = definition.end
        }
        return definitions
    }

    public func kind(ofLine line: Int) -> Kind? {
        kinds[line]
    }

    /// The lines as cmark counts them: broken at `\n`, `\r\n` (one Character) and `\r` only, not at a
    /// vertical tab, a form feed or U+2028, which `Character.isNewline` also takes.
    public static func lines(of markdown: String) -> [String] {
        markdown.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }).map(String.init)
    }

    /// cmark's `cmark_parse_reference_inline` (inlines.c) over a paragraph's content, byte for byte.
    private struct ReferenceParser {
        let bytes: [UInt8]

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
        }

        struct Definition {
            let label: String
            let destination: String
            /// Just past the line break that ends the definition.
            let end: Int
        }

        func definition(at start: Int) -> Definition? {
            var position = start
            func peek() -> UInt8 { position < bytes.count ? bytes[position] : 0 }
            func skipSpaces() {
                while peek() == 0x20 || peek() == 0x09 { position += 1 }
            }
            func skipLineEnd() -> Bool {
                var seen = false
                if peek() == 0x0D { position += 1; seen = true }
                if peek() == 0x0A { position += 1; seen = true }
                return seen || position >= bytes.count
            }
            func spaceAndNewline() {
                skipSpaces()
                if skipLineEnd() { skipSpaces() }
            }

            // The label: no unescaped bracket inside, at most 999 bytes, not blank.
            guard peek() == 0x5B else { return nil }
            position += 1
            let labelStart = position
            var length = 0
            while position < bytes.count, bytes[position] != 0x5B, bytes[position] != 0x5D {
                if bytes[position] == 0x5C, position + 1 < bytes.count, Self.isPunctuation(bytes[position + 1]) {
                    position += 2
                    length += 2
                } else {
                    position += 1
                    length += 1
                }
                if length > 999 { return nil }
            }
            guard peek() == 0x5D else { return nil }
            let label = String(decoding: bytes[labelStart..<position], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { return nil }
            position += 1
            guard peek() == 0x3A else { return nil } // ":"
            position += 1

            spaceAndNewline()
            guard let destination = destination(at: position) else { return nil }
            position += destination.length

            let beforeTitle = position
            spaceAndNewline()
            let title = position == beforeTitle ? 0 : titleLength(at: position)
            position = title > 0 ? position + title : beforeTitle
            skipSpaces()
            if !skipLineEnd() {
                // Something after the title: the definition may still end at its destination's line.
                guard title > 0 else { return nil }
                position = beforeTitle
                skipSpaces()
                guard skipLineEnd() else { return nil }
            }
            return Definition(label: label, destination: destination.text, end: position)
        }

        /// `manual_scan_link_url`: `<…>` on one line, or a run without spaces whose parentheses nest.
        private func destination(at start: Int) -> (text: String, length: Int)? {
            var index = start
            if index < bytes.count, bytes[index] == 0x3C { // "<"
                index += 1
                while index < bytes.count {
                    if bytes[index] == 0x3E { // ">"
                        index += 1
                        break
                    } else if bytes[index] == 0x5C {
                        index += 2
                    } else if bytes[index] == 0x0A || bytes[index] == 0x3C {
                        return nil
                    } else {
                        index += 1
                    }
                }
                guard index < bytes.count else { return nil }
                return (String(decoding: bytes[(start + 1)..<(index - 1)], as: UTF8.self), index - start)
            }
            var depth = 0
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x5C, index + 1 < bytes.count, Self.isPunctuation(bytes[index + 1]) {
                    index += 2
                } else if byte == 0x28 { // "("
                    depth += 1
                    index += 1
                    if depth > 32 { return nil }
                } else if byte == 0x29 { // ")"
                    if depth == 0 { break }
                    depth -= 1
                    index += 1
                } else if Self.isSpace(byte) {
                    if index == start { return nil }
                    break
                } else {
                    index += 1
                }
            }
            guard index < bytes.count else { return nil }
            return (String(decoding: bytes[start..<index], as: UTF8.self), index - start)
        }

        /// `scan_link_title`, the longest of `"…"`, `'…'` or `(…)` whose inner delimiters are all
        /// escaped, or 0.
        private func titleLength(at start: Int) -> Int {
            guard start < bytes.count else { return 0 }
            let open = bytes[start]
            let close: UInt8
            switch open {
            case 0x22, 0x27: close = open
            case 0x28: close = 0x29
            default: return 0
            }
            var longest = 0
            var index = start + 1
            while index < bytes.count, bytes[index] != 0 {
                let escaped = index - 1 > start && bytes[index - 1] == 0x5C
                if bytes[index] == close {
                    longest = index + 1 - start
                    if !escaped { break }
                } else if open == 0x28, bytes[index] == 0x28, !escaped {
                    break
                }
                index += 1
            }
            return longest
        }

        static func isPunctuation(_ byte: UInt8) -> Bool {
            (0x21...0x2F).contains(byte) || (0x3A...0x40).contains(byte) || (0x5B...0x60).contains(byte) || (0x7B...0x7E).contains(byte)
        }

        static func isSpace(_ byte: UInt8) -> Bool {
            byte == 0x20 || (0x09...0x0D).contains(byte)
        }
    }

    private static func isInQuote(_ node: UnsafeMutablePointer<cmark_node>) -> Bool {
        var parent = cmark_node_parent(node)
        while let current = parent {
            if cmark_node_get_type(current) == CMARK_NODE_BLOCK_QUOTE { return true }
            parent = cmark_node_parent(current)
        }
        return false
    }
}
