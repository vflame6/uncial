import Foundation

/// What the inline presentation hides and reveals: the delimiter ranges of every construct, the
/// bullets it re-draws, and the fenced blocks that reveal as a whole when the caret is inside.
nonisolated struct MarkerIndex: Equatable {
    static let empty = MarkerIndex(tokens: [])

    /// Sorted, non-overlapping.
    let hidden: [NSRange]
    /// Character indexes of `-`, `*` and `+` list markers, drawn as bullets.
    let bullets: Set<Int>
    /// Fenced code blocks including both fence lines; an unclosed one runs to its last code line.
    let blocks: [NSRange]

    init(tokens: [MarkdownHighlighter.Token]) {
        var hidden: [NSRange] = []
        var bullets: Set<Int> = []
        var blocks: [NSRange] = []
        var blockStart: Int?
        var blockEnd = 0
        for token in tokens {
            switch token.kind {
            case .image, .frontMatter:
                continue
            case .listItem(let bullet, _):
                if let bullet { bullets.insert(bullet) }
            case .fence:
                if let start = blockStart {
                    blocks.append(NSRange(location: start, length: NSMaxRange(token.range) - start))
                    blockStart = nil
                } else {
                    blockStart = token.range.location
                }
            case .code:
                blockEnd = NSMaxRange(token.range)
            default:
                break
            }
            hidden += token.markers
        }
        if let start = blockStart {
            blocks.append(NSRange(location: start, length: max(blockEnd, start) - start))
        }
        self.hidden = hidden.sorted { $0.location < $1.location }
        self.bullets = bullets
        self.blocks = blocks
    }

    func isHidden(_ index: Int) -> Bool {
        var low = 0
        var high = hidden.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let range = hidden[mid]
            if index < range.location {
                high = mid - 1
            } else if index >= NSMaxRange(range) {
                low = mid + 1
            } else {
                return true
            }
        }
        return false
    }

    func hasHidden(in range: NSRange) -> Bool {
        hidden.contains { NSIntersectionRange($0, range).length > 0 }
    }

    /// The paragraphs the selection touches, widened to any fenced block they are in.
    func revealedRange(for selection: NSRange, in text: NSString) -> NSRange {
        var range = text.lineRange(for: selection)
        for block in blocks where NSIntersectionRange(block, range).length > 0 || NSLocationInRange(range.location, block) {
            range = NSUnionRange(range, text.lineRange(for: block))
        }
        return range
    }
}
