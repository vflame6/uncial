import Foundation

/// What Return does inside a list item or block quote: continue it, or end an empty one.
nonisolated enum ListContinuation {
    // 1 quote prefixes, 2 indentation, 3 bullet, 4 number, 5 delimiter, 6 spacing, 7 task box with its spacing
    private static let item = try! NSRegularExpression(pattern: #"^((?:[ \t]{0,3}>[ \t]?)*)([ \t]*)(?:([-+*])|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?"#)
    private static let quote = try! NSRegularExpression(pattern: #"^((?:[ \t]{0,3}>[ \t]?)+)"#)

    /// The edit Return performs at `caret`, or nil for an ordinary line break. Inside an item the new
    /// line repeats the quote prefix, indentation and marker (ordered numbers incremented, task boxes
    /// unchecked) and takes the text after the caret with it; on an empty item the marker is removed.
    static func edit(in text: NSString, at caret: Int) -> AutoPairing.Edit? {
        let lineRange = text.lineRange(for: NSRange(location: caret, length: 0))
        var contentLength = lineRange.length
        while contentLength > 0, isLineBreak(text.character(at: lineRange.location + contentLength - 1)) {
            contentLength -= 1
        }
        let line = text.substring(with: NSRange(location: lineRange.location, length: contentLength))
        let whole = NSRange(location: 0, length: contentLength)
        let caretInLine = caret - lineRange.location
        let atEnd = caretInLine == contentLength
        if let match = item.firstMatch(in: line, range: whole) {
            guard caretInLine >= match.range.length else { return nil }
            let quotes = substring(line, match.range(at: 1))
            let quotesLength = (quotes as NSString).length
            if atEnd, match.range.length == contentLength {
                let marker = NSRange(location: lineRange.location + quotesLength, length: match.range.length - quotesLength)
                return AutoPairing.Edit(range: marker, replacement: "", selection: NSRange(location: marker.location, length: 0))
            }
            var prefix = quotes + substring(line, match.range(at: 2))
            if match.range(at: 3).location != NSNotFound {
                prefix += substring(line, match.range(at: 3))
            } else {
                prefix += String((Int(substring(line, match.range(at: 4))) ?? 0) + 1) + substring(line, match.range(at: 5))
            }
            prefix += substring(line, match.range(at: 6))
            if match.range(at: 7).location != NSNotFound {
                prefix += "[ ]" + substring(line, match.range(at: 7)).dropFirst(3)
            }
            return insertion(of: prefix, at: caret)
        }
        if let match = quote.firstMatch(in: line, range: whole) {
            guard caretInLine >= match.range.length else { return nil }
            if atEnd, match.range.length == contentLength {
                let prefix = NSRange(location: lineRange.location, length: match.range.length)
                return AutoPairing.Edit(range: prefix, replacement: "", selection: NSRange(location: prefix.location, length: 0))
            }
            return insertion(of: substring(line, match.range(at: 1)), at: caret)
        }
        return nil
    }

    private static func insertion(of prefix: String, at caret: Int) -> AutoPairing.Edit {
        let replacement = "\n" + prefix
        return AutoPairing.Edit(range: NSRange(location: caret, length: 0), replacement: replacement, selection: NSRange(location: caret + (replacement as NSString).length, length: 0))
    }

    private static func substring(_ line: String, _ range: NSRange) -> String {
        range.location == NSNotFound ? "" : (line as NSString).substring(with: range)
    }

    private static func isLineBreak(_ unit: unichar) -> Bool {
        unit == 0x0A || unit == 0x0D
    }
}
