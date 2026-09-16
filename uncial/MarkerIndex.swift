import Foundation

/// What the inline presentation hides and reveals: the delimiter ranges of every construct, the
/// bullets it re-draws, and the fenced blocks that reveal as a whole when the caret is inside.
/// Image markers hide only for the images that loaded (`resolvedImages`: token locations).
/// `diagramBlocks` are the mermaid fences (`InlineStyle.diagramBlocks`); one whose picture is drawn
/// (`resolvedDiagrams`: opening fence locations) hides entirely except for its last newline, which
/// keeps one line for the picture to hang under.
nonisolated struct MarkerIndex: Equatable {
    static let empty = MarkerIndex(tokens: [])

    /// Sorted, non-overlapping.
    let hidden: [NSRange]
    /// Character indexes of `-`, `*` and `+` list markers, drawn as bullets.
    let bullets: Set<Int>
    /// Fenced code blocks including both fence lines; an unclosed one runs to its last code line.
    let blocks: [NSRange]
    /// The mermaid fences, pictured or not: a reveal change touching one re-applies attributes.
    let diagramBlocks: [NSRange]

    init(tokens: [MarkdownHighlighter.Token], resolvedImages: Set<Int> = [], diagramBlocks: [NSRange] = [], resolvedDiagrams: Set<Int> = []) {
        var hidden: [NSRange] = []
        var bullets: Set<Int> = []
        var blocks: [NSRange] = []
        var blockStart: Int?
        var blockEnd = 0
        func close(_ start: Int, at end: Int) {
            let block = NSRange(location: start, length: max(end, start) - start)
            blocks.append(block)
            if resolvedDiagrams.contains(start) {
                hidden.append(block)
            }
        }
        for token in tokens {
            switch token.kind {
            case .frontMatter:
                continue
            case .image:
                if resolvedImages.contains(token.range.location) { hidden += token.markers }
                continue
            case .listItem(let bullet, _):
                if let bullet { bullets.insert(bullet) }
            case .fence:
                if let start = blockStart {
                    close(start, at: NSMaxRange(token.range))
                    blockStart = nil
                } else {
                    blockStart = token.range.location
                    blockEnd = NSMaxRange(token.range)
                }
            case .code:
                blockEnd = NSMaxRange(token.range)
            default:
                break
            }
            hidden += token.markers
        }
        if let start = blockStart {
            close(start, at: blockEnd)
        }
        self.hidden = Self.merged(hidden)
        self.bullets = bullets
        self.blocks = blocks
        self.diagramBlocks = diagramBlocks
    }

    /// Sorted by location, with overlapping ranges joined.
    static func merged(_ ranges: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for range in ranges.sorted(by: { $0.location < $1.location }) {
            if let previous = result.last, range.location < NSMaxRange(previous) {
                result[result.count - 1] = NSUnionRange(previous, range)
            } else {
                result.append(range)
            }
        }
        return result
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

    /// Whether a picture-drawn block touches `range` (so a reveal change must re-apply attributes).
    func hasDiagram(touching range: NSRange) -> Bool {
        diagramBlocks.contains { NSIntersectionRange($0, range).length > 0 || NSLocationInRange(range.location, $0) }
    }
}
