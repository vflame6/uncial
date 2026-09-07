import Foundation

/// cmark's `data-sourcepos="L1:C1-L2:C2"` attributes, which the app uses to sync scrolling and to
/// draw a source-line gutter.
public enum SourcePositions {
    private static let attribute = try! NSRegularExpression(pattern: #"data-sourcepos="(\d+):(\d+)-(\d+):(\d+)""#)
    private static let element = try! NSRegularExpression(pattern: #"<([a-z][a-z0-9]*)([^>]*?)\sdata-sourcepos="(\d+):(\d+)-(\d+):(\d+)""#)
    private static let codeBlock = try! NSRegularExpression(pattern: #"<pre data-sourcepos="(\d+):(\d+)-(\d+):(\d+)"><code([^>]*)>([\s\S]*?)</code></pre>"#)
    private static let unnumbered: Set<String> = ["pre", "tr", "td", "th"]

    /// Adds `offset` to every line number so positions match the document the editor shows
    /// (cmark never sees the front matter, so its lines start after it).
    public static func shift(_ html: String, by offset: Int) -> String {
        guard offset != 0, html.contains("data-sourcepos") else { return html }
        let source = html as NSString
        var output = ""
        var cursor = 0
        for match in attribute.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let numbers = (1...4).map { Int(source.substring(with: match.range(at: $0))) ?? 0 }
            output += "data-sourcepos=\"\(numbers[0] + offset):\(numbers[1])-\(numbers[2] + offset):\(numbers[3])\""
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        return output
    }

    /// Adds `data-line` (the first source line) to each block that starts a new line, in document
    /// order, so a gutter can show it: never on `pre` (its lines get their own numbers below), never
    /// on table rows and cells. Every line inside a code block becomes
    /// `<span class="line" data-line="N">`; fenced blocks start after the fence, indented ones on
    /// their first line (only a fenced block's range spans more lines than it has code lines).
    public static func annotate(_ html: String) -> String {
        guard html.contains("data-sourcepos") else { return html }
        var lastLine = 0
        let labeled = replacing(element, in: html) { match, source in
            let tag = source.substring(with: match.range(at: 1))
            let line = Int(source.substring(with: match.range(at: 3))) ?? 0
            guard !unnumbered.contains(tag), line != lastLine else { return nil }
            lastLine = line
            let headLength = NSMaxRange(match.range(at: 2)) - match.range.location
            let head = source.substring(with: NSRange(location: match.range.location, length: headLength))
            let tail = source.substring(with: NSRange(location: match.range.location + headLength, length: match.range.length - headLength))
            return head + " data-line=\"\(line)\"" + tail
        }
        return replacing(codeBlock, in: labeled) { match, source in
            let start = Int(source.substring(with: match.range(at: 1))) ?? 0
            let end = Int(source.substring(with: match.range(at: 3))) ?? start
            let endColumn = Int(source.substring(with: match.range(at: 4))) ?? 1
            let content = source.substring(with: match.range(at: 6))
            var lines = content.components(separatedBy: "\n")
            if lines.last == "" { lines.removeLast() }
            let spanned = endColumn == 0 ? end - start : end - start + 1
            let first = spanned > lines.count ? start + 1 : start
            let numbered = lines.enumerated().map { "<span class=\"line\" data-line=\"\(first + $0.offset)\">\($0.element)</span>" }
            let opening = source.substring(with: NSRange(location: match.range.location, length: match.range(at: 6).location - match.range.location))
            return opening + numbered.joined(separator: "\n") + (content.hasSuffix("\n") ? "\n" : "") + "</code></pre>"
        }
    }

    /// Rebuilds `html` with each match replaced by `transform`'s result (nil keeps the original).
    private static func replacing(_ regex: NSRegularExpression, in html: String, _ transform: (NSTextCheckingResult, NSString) -> String?) -> String {
        let source = html as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            guard let replacement = transform(match, source) else { continue }
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += replacement
            cursor = NSMaxRange(match.range)
        }
        output += source.substring(from: cursor)
        return output
    }
}
