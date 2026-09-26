import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// The lines of a Markdown body that cmark takes as they are: fenced code with its fences, indented
/// code, HTML blocks. The editor's tokenizer asks it so Live Preview hides no Markdown in text the
/// page shows as written: its line regexes knew no indented code, no fence indented inside a list
/// item and no HTML block (REF-3, 2026-09-26). Lines are the 0-based lines of the text given; front
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

    private let kinds: [Int: Kind]

    public init(_ markdown: String) {
        var kinds: [Int: Kind] = [:]
        // Lines as cmark counts them: `\r\n` is one break (and one Character).
        let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
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
                // Lines in a block quote carry its `>` prefixes: the editor reads those itself.
                guard first >= 0, last >= first, !Self.isInQuote(node) else { continue }
                switch cmark_node_get_type(node) {
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
    }

    public func kind(ofLine line: Int) -> Kind? {
        kinds[line]
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
