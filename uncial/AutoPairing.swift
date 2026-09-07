import Foundation

/// Decides what a keystroke does in the source editor when auto-pairing is on, and remembers the
/// pairs it inserted so their closers can be skipped, grown or deleted. Positions are UTF-16
/// offsets into the text the caller passes in; entries that no longer match the text are dropped.
nonisolated struct AutoPairing: Equatable {
    struct Pair: Equatable {
        let open: unichar
        let close: unichar
        /// Longest run a symmetric marker may grow to by typing it inside an empty pair (`**|**`).
        let growth: Int

        init(_ open: Character, _ close: Character, growth: Int = 1) {
            self.open = open.utf16.first!
            self.close = close.utf16.first!
            self.growth = growth
        }

        var isSymmetric: Bool { open == close }
        var opener: String { String(utf16CodeUnits: [open], count: 1) }
        var closer: String { String(utf16CodeUnits: [close], count: 1) }
    }

    /// An auto-inserted pair: the opener run and the closer run it still expects to skip.
    struct Tracked: Equatable {
        var pair: Pair
        var open: NSRange
        var close: NSRange
    }

    /// Replace `range` with `replacement`, then select `selection`. An empty range and replacement is a caret move.
    struct Edit: Equatable {
        let range: NSRange
        let replacement: String
        let selection: NSRange
    }

    static let autoClosing: [Pair] = [
        Pair("(", ")"), Pair("[", "]"), Pair("{", "}"),
        Pair("`", "`", growth: 3), Pair("*", "*", growth: 3), Pair("_", "_", growth: 3), Pair("\"", "\""),
    ]
    static let wrapOnly: [Pair] = [Pair("<", ">"), Pair("~", "~"), Pair("'", "'")]
    /// Characters an opener may be typed in front of and still get its partner (besides whitespace and the end).
    static let closeBefore = Set(")]}>.,;:!?*_~`\"".utf16)
    private static let emphasis = Set("*_".utf16)
    private static let backtick: unichar = 0x60
    private static let space: unichar = 0x20

    private(set) var tracked: [Tracked] = []

    mutating func reset() {
        tracked = []
    }

    // MARK: Keystrokes

    /// One typed character; anything longer is pasted or composed and left alone.
    mutating func typed(_ string: String, in text: NSString, selection: NSRange) -> Edit? {
        guard string.utf16.count == 1, let c = string.utf16.first else { return nil }
        if selection.length > 0 { return wrap(selection, with: c, in: text) }
        prune(in: text)
        let caret = selection.location
        if c == Self.space { return whitespace(string, at: caret) }
        if let index = tracked.firstIndex(where: { $0.close.location == caret && $0.pair.close == c }) {
            return closer(string, at: caret, entry: index)
        }
        guard let pair = Self.autoClosing.first(where: { $0.open == c }) else { return nil }
        let next: unichar? = caret < text.length ? text.character(at: caret) : nil
        if let next, !Self.isWhitespace(next), !Self.closeBefore.contains(next) { return nil }
        if pair.isSymmetric {
            let previous: unichar? = caret > 0 ? text.character(at: caret - 1) : nil
            if let previous, previous == c || Self.isWordCharacter(previous) { return nil }
            if next == c { return nil }
        }
        map(NSRange(location: caret, length: 0), replacementLength: 2)
        tracked.append(Tracked(pair: pair, open: NSRange(location: caret, length: 1), close: NSRange(location: caret + 1, length: 1)))
        return Edit(range: NSRange(location: caret, length: 0), replacement: pair.opener + pair.closer, selection: NSRange(location: caret + 1, length: 0))
    }

    /// Return: drops the closer of an empty `*`/`_` pair, or turns ```` ```|``` ```` into a fenced block.
    mutating func newline(in text: NSString, selection: NSRange) -> Edit? {
        guard selection.length == 0 else { return nil }
        prune(in: text)
        let caret = selection.location
        if let edit = whitespace("\n", at: caret) { return edit }
        guard let index = tracked.firstIndex(where: {
            $0.close.location == caret && $0.pair.open == Self.backtick && $0.open.length == 3 && Self.startsLine($0.open.location, in: text)
        }) else { return nil }
        tracked.remove(at: index)
        map(NSRange(location: caret, length: 0), replacementLength: 2)
        return Edit(range: NSRange(location: caret, length: 0), replacement: "\n\n", selection: NSRange(location: caret + 1, length: 0))
    }

    /// Backspace inside an empty pair removes one character from each side.
    mutating func deleteBackward(in text: NSString, selection: NSRange) -> Edit? {
        guard selection.length == 0 else { return nil }
        prune(in: text)
        let caret = selection.location
        guard let index = tracked.firstIndex(where: { $0.close.location == caret && NSMaxRange($0.open) == caret }) else { return nil }
        var entry = tracked.remove(at: index)
        let range = NSRange(location: caret - 1, length: 2)
        map(range, replacementLength: 0)
        entry.open.length -= 1
        entry.close.location -= 1
        entry.close.length -= 1
        if entry.close.length > 0 { tracked.append(entry) }
        return Edit(range: range, replacement: "", selection: NSRange(location: caret - 1, length: 0))
    }

    // MARK: Changes made by others

    /// Moves tracked positions through an edit this type did not produce (typing, paste, undo, replace).
    mutating func textChanged(in range: NSRange, replacementLength: Int) {
        map(range, replacementLength: replacementLength)
    }

    /// Forgets pairs the caret is no longer inside of.
    mutating func selectionChanged(to selection: NSRange) {
        tracked.removeAll { NSMaxRange($0.open) > selection.location || NSMaxRange(selection) > $0.close.location }
    }

    // MARK: Rules

    private mutating func wrap(_ selection: NSRange, with c: unichar, in text: NSString) -> Edit? {
        guard let pair = (Self.autoClosing + Self.wrapOnly).first(where: { $0.open == c }) else { return nil }
        map(selection, replacementLength: selection.length + 2)
        let replacement = pair.opener + text.substring(with: selection) + pair.closer
        return Edit(range: selection, replacement: replacement, selection: NSRange(location: selection.location + 1, length: selection.length))
    }

    /// Whitespace right after an empty `*`/`_` pair: it can never become emphasis, so the closer goes.
    private mutating func whitespace(_ string: String, at caret: Int) -> Edit? {
        guard let index = tracked.firstIndex(where: {
            $0.close.location == caret && NSMaxRange($0.open) == caret && Self.emphasis.contains($0.pair.open)
        }) else { return nil }
        let entry = tracked.remove(at: index)
        map(entry.close, replacementLength: 1)
        return Edit(range: entry.close, replacement: string, selection: NSRange(location: caret + 1, length: 0))
    }

    /// The closer's character typed right before a tracked closer: grow an empty marker pair, else skip.
    private mutating func closer(_ string: String, at caret: Int, entry index: Int) -> Edit? {
        var entry = tracked.remove(at: index)
        if entry.pair.isSymmetric, entry.pair.growth > 1, NSMaxRange(entry.open) == caret {
            guard entry.open.length < entry.pair.growth else {
                tracked.append(entry)
                return nil
            }
            map(NSRange(location: caret, length: 0), replacementLength: 2)
            entry.open.length += 1
            entry.close.location += 1
            entry.close.length += 1
            tracked.append(entry)
            return Edit(range: NSRange(location: caret, length: 0), replacement: string + string, selection: NSRange(location: caret + 1, length: 0))
        }
        entry.close.location += 1
        entry.close.length -= 1
        if entry.close.length > 0 { tracked.append(entry) }
        return Edit(range: NSRange(location: caret, length: 0), replacement: "", selection: NSRange(location: caret + 1, length: 0))
    }

    /// Shifts or drops entries for a replacement of `range` by `replacementLength` characters.
    private mutating func map(_ range: NSRange, replacementLength: Int) {
        let delta = replacementLength - range.length
        tracked = tracked.compactMap { entry in
            var entry = entry
            if NSMaxRange(range) <= entry.open.location {
                entry.open.location += delta
                entry.close.location += delta
            } else if range.location >= NSMaxRange(entry.close) {
                return entry
            } else if range.location >= NSMaxRange(entry.open), NSMaxRange(range) <= entry.close.location {
                entry.close.location += delta
            } else {
                return nil
            }
            return entry
        }
    }

    /// Drops entries whose delimiters are no longer in the text (undo, Replace All, reload).
    private mutating func prune(in text: NSString) {
        tracked.removeAll { entry in
            NSMaxRange(entry.close) > text.length
                || text.substring(with: entry.open) != String(repeating: entry.pair.opener, count: entry.open.length)
                || text.substring(with: entry.close) != String(repeating: entry.pair.closer, count: entry.close.length)
        }
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        UnicodeScalar(unit).map(CharacterSet.whitespacesAndNewlines.contains) ?? false
    }

    private static func isWordCharacter(_ unit: unichar) -> Bool {
        UnicodeScalar(unit).map(CharacterSet.alphanumerics.contains) ?? false
    }

    /// True when at most three spaces separate `location` from the start of its line.
    private static func startsLine(_ location: Int, in text: NSString) -> Bool {
        var index = location
        while index > 0, location - index < 3, text.character(at: index - 1) == space {
            index -= 1
        }
        return index == 0 || text.character(at: index - 1) == 0x0A || text.character(at: index - 1) == 0x0D
    }
}
