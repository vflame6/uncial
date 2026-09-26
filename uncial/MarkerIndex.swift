import Foundation

/// What the inline presentation hides and reveals: the delimiter ranges of every construct, the
/// bullets it re-draws, and the fenced blocks (``` and `$$`) that reveal as a whole when the caret
/// is inside. Image markers hide only for the images that loaded (`resolvedImages`: token
/// locations). A diagram whose picture is drawn (`resolvedDiagrams`: opening fence locations) hides entirely
/// except for its last newline, which keeps one line for the picture to hang under; a formula whose
/// picture is drawn (`resolvedMath`: token or block start → anchor) hides everything but its anchor,
/// the one character laid out as a box of the picture's size.
nonisolated struct MarkerIndex: Equatable {
    static let empty = MarkerIndex(tokens: [])

    /// Sorted, non-overlapping.
    let hidden: [NSRange]
    /// Character indexes of `-`, `*` and `+` list markers, drawn as bullets.
    let bullets: Set<Int>
    /// `bullets` in order, for `hasBullet(in:)`.
    private let sortedBullets: [Int]
    /// Fenced code and math blocks including both fence lines (an unclosed one runs to its last line),
    /// and callouts: what reveals as a whole.
    let blocks: [NSRange]
    /// Sorted character indexes that stand for a formula's picture.
    let anchors: [Int]

    /// `calloutBlocks` (`MarkdownHighlighter.calloutBlocks`) reveal as a whole too.
    init(tokens: [MarkdownHighlighter.Token], resolvedImages: Set<Int> = [], resolvedDiagrams: Set<Int> = [], resolvedMath: [Int: Int] = [:], calloutBlocks: [NSRange] = []) {
        var hidden: [NSRange] = []
        var bullets: Set<Int> = []
        var blocks: [NSRange] = []
        var blockStart: Int?
        var blockEnd = 0
        /// Closes the block; true when it hides as a formula, whose closing fence keeps the anchor visible.
        func close(_ start: Int, at end: Int) -> Bool {
            let block = NSRange(location: start, length: max(end, start) - start)
            blocks.append(block)
            if resolvedDiagrams.contains(start) {
                hidden.append(block)
            } else if let anchor = resolvedMath[start] {
                hidden += Self.excluding(anchor, from: block)
                return true
            }
            return false
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
            case .fence, .mathFence:
                if let start = blockStart {
                    blockStart = nil
                    if close(start, at: NSMaxRange(token.range)) { continue }
                } else {
                    blockStart = token.range.location
                    blockEnd = NSMaxRange(token.range)
                }
            case .code:
                blockEnd = NSMaxRange(token.range)
            case .math:
                if blockStart != nil {
                    blockEnd = NSMaxRange(token.range)
                } else if !token.markers.isEmpty {
                    if let anchor = resolvedMath[token.range.location] {
                        hidden += Self.excluding(anchor, from: token.range)
                        continue
                    }
                }
            default:
                break
            }
            hidden += token.markers
        }
        if let start = blockStart {
            _ = close(start, at: blockEnd)
        }
        self.hidden = Self.merged(hidden)
        self.bullets = bullets
        self.sortedBullets = bullets.sorted()
        self.blocks = blocks + calloutBlocks
        self.anchors = resolvedMath.values.sorted()
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

    /// `range` without the character at `anchor`.
    static func excluding(_ anchor: Int, from range: NSRange) -> [NSRange] {
        [NSRange(location: range.location, length: anchor - range.location),
         NSRange(location: anchor + 1, length: NSMaxRange(range) - anchor - 1)].filter { $0.length > 0 }
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

    /// Whether a hidden range overlaps `range`. Binary search: the glyph delegate asks for every glyph
    /// run, and a scan over thousands of markers cost 50–90 ms per keystroke (PERF-3).
    func hasHidden(in range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        // The first hidden range that ends after `range` starts; `hidden` is sorted and non-overlapping,
        // so the ends are in order too.
        var low = 0
        var high = hidden.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(hidden[mid]) <= range.location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        while low < hidden.count, hidden[low].location < NSMaxRange(range) {
            if hidden[low].length > 0 { return true }
            low += 1
        }
        return false
    }

    /// Whether a bullet lies inside `range`, by binary search as `hasHidden(in:)`.
    func hasBullet(in range: NSRange) -> Bool {
        var low = 0
        var high = sortedBullets.count
        while low < high {
            let mid = (low + high) / 2
            if sortedBullets[mid] < range.location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low < sortedBullets.count && sortedBullets[low] < NSMaxRange(range)
    }

    func isAnchor(_ index: Int) -> Bool {
        !anchors(in: NSRange(location: index, length: 1)).isEmpty
    }

    /// The anchors inside `range`, in order.
    func anchors(in range: NSRange) -> ArraySlice<Int> {
        var low = 0
        var high = anchors.count
        while low < high {
            let mid = (low + high) / 2
            if anchors[mid] < range.location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        var end = low
        while end < anchors.count, anchors[end] < NSMaxRange(range) {
            end += 1
        }
        return anchors[low..<end]
    }

    func hasAnchor(in range: NSRange) -> Bool {
        !anchors(in: range).isEmpty
    }

    /// The paragraphs the selection touches, widened to any fenced block they are in. The selection
    /// and the blocks are clipped to `text`: they may come from a longer text (an edit still being
    /// processed, a reload), and `lineRange(for:)` raises past the end.
    func revealedRange(for selection: NSRange, in text: NSString) -> NSRange {
        let length = text.length
        let start = min(selection.location, length)
        var range = text.lineRange(for: NSRange(location: start, length: min(selection.length, length - start)))
        for block in blocks where block.location <= length {
            let block = NSRange(location: block.location, length: min(NSMaxRange(block), length) - block.location)
            guard NSIntersectionRange(block, range).length > 0 || NSLocationInRange(range.location, block) else { continue }
            range = NSUnionRange(range, text.lineRange(for: block))
        }
        return range
    }
}
