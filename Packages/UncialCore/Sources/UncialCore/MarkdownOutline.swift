import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// A flat reading of a document's first blocks with the styling that shapes a page: headings,
/// list markers, quotes, code, rules, table rows and the inline styles of their text. For renderers
/// that cannot show HTML, such as the thumbnail extension, which draws it with AppKit. Markers
/// are gone; HTML blocks and front matter are skipped. A callout's title (`Callouts`) is a strong
/// paragraph of its own, the marker gone.
public enum MarkdownOutline {
    public struct Run: Equatable, Sendable {
        public var text: String
        public var isStrong = false
        public var isEmphasis = false
        public var isCode = false
        public var isStrikethrough = false
        public var isLink = false
        /// The alt text of an image.
        public var isImage = false

        public init(_ text: String, isStrong: Bool = false, isEmphasis: Bool = false, isCode: Bool = false,
                    isStrikethrough: Bool = false, isLink: Bool = false, isImage: Bool = false) {
            self.text = text
            self.isStrong = isStrong
            self.isEmphasis = isEmphasis
            self.isCode = isCode
            self.isStrikethrough = isStrikethrough
            self.isLink = isLink
            self.isImage = isImage
        }
    }

    public enum Kind: Equatable, Sendable {
        case heading(level: Int)
        case paragraph
        /// `marker` is what the page shows: `•`, `3.`, `☐` or `☑`.
        case listItem(marker: String)
        /// One run, the literal text; a code block ends with a newline like cmark's literal.
        case code
        case rule
        case tableRow(cells: [[Run]], isHeader: Bool)
    }

    public struct Block: Equatable, Sendable {
        public var kind: Kind
        public var runs: [Run]
        /// Enclosing lists: 1 for a top-level item, also for paragraphs and code inside one.
        public var listDepth: Int
        public var quoteDepth: Int

        public init(_ kind: Kind, runs: [Run] = [], listDepth: Int = 0, quoteDepth: Int = 0) {
            self.kind = kind
            self.runs = runs
            self.listDepth = listDepth
            self.quoteDepth = quoteDepth
        }

        public var text: String { runs.map(\.text).joined() }
    }

    /// The first `limit` blocks of the document body, in order.
    public static func blocks(in markdown: String, limit: Int = 100) -> [Block] {
        let body = FrontMatter.split(markdown).body
        return GFMRenderer.withDocument(body) { document, _ in
            let walker = Walker(limit: limit)
            walker.walk(document)
            return walker.blocks
        } ?? []
    }

    private final class Walker {
        let limit: Int
        var blocks: [Block] = []

        private var kind: Kind?
        private var runs: [Run] = []
        private var lists: [(ordered: Bool, next: Int)] = []
        private var pendingMarker: String?
        private var quoteDepth = 0
        private var strong = 0
        private var emphasis = 0
        private var strikethrough = 0
        private var link = 0
        private var image = 0
        /// Set while the paragraph being read is a callout's first line: its title, strong, ends at the
        /// first soft break. `calloutMarkerRemaining` is how much of the marker the text nodes still hold
        /// (cmark keeps `[` as a text node of its own).
        private var inCalloutTitle = false
        private var calloutMarkerRemaining = 0
        private var cells: [[Run]] = []
        private var cell: [Run]?
        private var rowIsHeader = false

        init(limit: Int) {
            self.limit = limit
        }

        func walk(_ document: UnsafeMutablePointer<cmark_node>) {
            guard let iterator = cmark_iter_new(document) else { return }
            defer { cmark_iter_free(iterator) }
            while blocks.count < limit {
                let event = cmark_iter_next(iterator)
                guard event != CMARK_EVENT_DONE, let node = cmark_iter_get_node(iterator) else { return }
                if event == CMARK_EVENT_ENTER {
                    enter(node)
                } else {
                    exit(node)
                }
            }
        }

        private func enter(_ node: UnsafeMutablePointer<cmark_node>) {
            switch cmark_node_get_type(node) {
            case CMARK_NODE_BLOCK_QUOTE:
                quoteDepth += 1
            case CMARK_NODE_LIST:
                lists.append((cmark_node_get_list_type(node) == CMARK_ORDERED_LIST, Int(cmark_node_get_list_start(node))))
            case CMARK_NODE_ITEM:
                pendingMarker = marker(for: node)
            case CMARK_NODE_HEADING:
                flushMarker()
                begin(.heading(level: Int(cmark_node_get_heading_level(node))))
            case CMARK_NODE_PARAGRAPH:
                begin(pendingMarker.map { .listItem(marker: $0) } ?? .paragraph)
                // As on the page, only a blockquote's first paragraph opens a callout.
                if kind == .paragraph, cell == nil, let quote = cmark_node_parent(node), cmark_node_get_type(quote) == CMARK_NODE_BLOCK_QUOTE,
                   cmark_node_first_child(quote) == node, let marker = Callouts.marker(in: leadingText(of: node)) {
                    inCalloutTitle = true
                    calloutMarkerRemaining = marker.length
                    if marker.title.isEmpty {
                        append(marker.defaultTitle)
                    }
                }
            case CMARK_NODE_CODE_BLOCK:
                flushMarker()
                emit(.code, runs: [Run(literal(of: node), isCode: true)])
            case CMARK_NODE_THEMATIC_BREAK:
                flushMarker()
                emit(.rule, runs: [])
            case CMARK_NODE_TEXT:
                var text = literal(of: node)
                if calloutMarkerRemaining > 0 {
                    let length = (text as NSString).length
                    guard length > calloutMarkerRemaining else {
                        calloutMarkerRemaining -= length
                        break
                    }
                    text = (text as NSString).substring(from: calloutMarkerRemaining)
                    calloutMarkerRemaining = 0
                }
                append(text)
            case CMARK_NODE_SOFTBREAK:
                if inCalloutTitle {
                    inCalloutTitle = false
                    end()
                    begin(.paragraph)
                } else {
                    append(" ")
                }
            case CMARK_NODE_LINEBREAK:
                append("\n")
            case CMARK_NODE_CODE:
                append(literal(of: node), code: true)
            case CMARK_NODE_EMPH:
                emphasis += 1
            case CMARK_NODE_STRONG:
                strong += 1
            case CMARK_NODE_LINK:
                link += 1
            case CMARK_NODE_IMAGE:
                image += 1
                if cmark_node_first_child(node) == nil {
                    append("Image")
                }
            default:
                switch String(cString: cmark_node_get_type_string(node)) {
                case "strikethrough":
                    strikethrough += 1
                case "table":
                    flushMarker()
                case "table_header", "table_row":
                    rowIsHeader = String(cString: cmark_node_get_type_string(node)) == "table_header"
                    cells = []
                case "table_cell":
                    cell = []
                default:
                    break
                }
            }
        }

        private func exit(_ node: UnsafeMutablePointer<cmark_node>) {
            switch cmark_node_get_type(node) {
            case CMARK_NODE_BLOCK_QUOTE:
                quoteDepth -= 1
            case CMARK_NODE_LIST:
                lists.removeLast()
            case CMARK_NODE_ITEM:
                if let marker = pendingMarker {
                    emit(.listItem(marker: marker), runs: [])
                }
            case CMARK_NODE_HEADING, CMARK_NODE_PARAGRAPH:
                end()
                inCalloutTitle = false
                calloutMarkerRemaining = 0
            case CMARK_NODE_EMPH:
                emphasis -= 1
            case CMARK_NODE_STRONG:
                strong -= 1
            case CMARK_NODE_LINK:
                link -= 1
            case CMARK_NODE_IMAGE:
                image -= 1
            default:
                switch String(cString: cmark_node_get_type_string(node)) {
                case "strikethrough":
                    strikethrough -= 1
                case "table_header", "table_row":
                    emit(.tableRow(cells: cells, isHeader: rowIsHeader), runs: [])
                case "table_cell":
                    if let cell { cells.append(cell) }
                    cell = nil
                default:
                    break
                }
            }
        }

        private func marker(for node: UnsafeMutablePointer<cmark_node>) -> String {
            if String(cString: cmark_node_get_type_string(node)) == "tasklist" {
                return cmark_gfm_extensions_get_tasklist_item_checked(node) ? "☑" : "☐"
            }
            guard let list = lists.last else { return "•" }
            guard list.ordered else { return "•" }
            lists[lists.count - 1].next += 1
            return "\(list.next)."
        }

        /// The text a paragraph starts with, across its leading text nodes.
        private func leadingText(of paragraph: UnsafeMutablePointer<cmark_node>) -> String {
            var text = ""
            var child = cmark_node_first_child(paragraph)
            while let node = child, cmark_node_get_type(node) == CMARK_NODE_TEXT {
                text += literal(of: node)
                child = cmark_node_next(node)
            }
            return text
        }

        private func literal(of node: UnsafeMutablePointer<cmark_node>) -> String {
            cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
        }

        /// The bullet of an item whose first block is not a paragraph (code, a rule, a heading, a table),
        /// on a line of its own before that block (BUG-21: code dropped it, a heading got it after).
        private func flushMarker() {
            if let marker = pendingMarker {
                emit(.listItem(marker: marker), runs: [])
            }
        }

        private func begin(_ kind: Kind) {
            self.kind = kind
            runs = []
        }

        private func end() {
            guard let kind else { return }
            emit(kind, runs: runs)
            self.kind = nil
            runs = []
        }

        private func emit(_ kind: Kind, runs: [Run]) {
            if case .listItem = kind { pendingMarker = nil }
            blocks.append(Block(kind, runs: runs, listDepth: lists.count, quoteDepth: quoteDepth))
        }

        private func append(_ text: String, code: Bool = false) {
            guard !text.isEmpty else { return }
            let run = Run(text, isStrong: strong > 0 || inCalloutTitle, isEmphasis: emphasis > 0, isCode: code,
                          isStrikethrough: strikethrough > 0, isLink: link > 0, isImage: image > 0)
            if cell != nil {
                cell?.append(run)
            } else if kind != nil {
                runs.append(run)
            }
        }
    }
}
