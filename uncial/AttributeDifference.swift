import AppKit

/// Where a text's attributes differ from the ones it should have, so that a styling pass can change
/// those stretches and leave the rest alone. A layout manager lays out again whatever its text storage
/// reports as edited: a pass that rewrote every attribute had the whole document laid out again, from
/// estimates, for one changed line.
enum AttributeDifference {
    /// The lines of `current` whose attributes are not `target`'s, in order, neighbors joined. The two
    /// hold the same text, whose line breaks `lines` knows.
    static func lines(of current: NSAttributedString, differingFrom target: NSAttributedString, lines: LineIndex) -> [NSRange] {
        let length = min(current.length, target.length)
        guard length > 0, !current.isEqual(to: target) else { return [] }
        var ranges: [NSRange] = []
        // Halves that are the same are done with in one comparison, so one changed line among thousands
        // costs about two readings of the text.
        func visit(_ lower: Int, _ upper: Int) {
            let start = lines.start(ofLine: lower)
            let range = NSRange(location: start, length: min(lines.start(ofLine: upper), length) - start)
            guard range.length > 0 else { return }
            // The first character settles most of a text that changed everywhere (another theme).
            let startsAlike = (current.attributes(at: start, effectiveRange: nil) as NSDictionary).isEqual(to: target.attributes(at: start, effectiveRange: nil))
            if startsAlike, current.attributedSubstring(from: range).isEqual(to: target.attributedSubstring(from: range)) { return }
            guard upper - lower > 1 else {
                if let last = ranges.last, NSMaxRange(last) == range.location {
                    ranges[ranges.count - 1] = NSUnionRange(last, range)
                } else {
                    ranges.append(range)
                }
                return
            }
            let middle = (lower + upper) / 2
            visit(lower, middle)
            visit(middle, upper)
        }
        visit(0, lines.count)
        return ranges
    }
}
