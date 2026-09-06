import Foundation

/// cmark's `data-sourcepos="L1:C1-L2:C2"` attributes, which the app uses to sync scrolling.
public enum SourcePositions {
    private static let attribute = try! NSRegularExpression(pattern: #"data-sourcepos="(\d+):(\d+)-(\d+):(\d+)""#)

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
}
