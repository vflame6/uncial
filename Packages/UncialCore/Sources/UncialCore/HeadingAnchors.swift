import Foundation

/// Adds GitHub-style `id` attributes to headings so `[link](#section)` works.
public enum HeadingAnchors {
    private static let heading = try! NSRegularExpression(
        pattern: #"<h([1-6])(\s[^>]*)?>(.*?)</h\1>"#,
        options: [.dotMatchesLineSeparators, .caseInsensitive]
    )
    private static let tag = try! NSRegularExpression(pattern: #"<[^>]+>"#)
    private static let idAttribute = try! NSRegularExpression(pattern: #"\sid\s*="#, options: [.caseInsensitive])

    public static func addIDs(to html: String) -> String {
        let source = html as NSString
        var used: [String: Int] = [:]
        var output = ""
        var cursor = 0
        for match in heading.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let level = source.substring(with: match.range(at: 1))
            let attributes = match.range(at: 2).location == NSNotFound ? "" : source.substring(with: match.range(at: 2))
            let inner = source.substring(with: match.range(at: 3))
            let attributeRange = NSRange(location: 0, length: (attributes as NSString).length)
            if idAttribute.firstMatch(in: attributes, range: attributeRange) != nil {
                output += source.substring(with: match.range)
            } else {
                let base = slug(for: inner)
                let seen = used[base, default: 0]
                used[base] = seen + 1
                let id = seen == 0 ? base : "\(base)-\(seen)"
                output += "<h\(level) id=\"\(id)\"\(attributes)>\(inner)</h\(level)>"
            }
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        return output
    }

    /// GitHub's slug: strip tags, lowercase, keep letters/digits/marks/`_`/`-`, spaces → `-`.
    public static func slug(for text: String) -> String {
        let withoutTags = tag.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: ""
        )
        let plain = HTMLEscaping.unescape(withoutTags).lowercased()
        var slug = ""
        for scalar in plain.unicodeScalars {
            switch scalar {
            case " ":
                slug.append("-")
            case "-", "_":
                slug.unicodeScalars.append(scalar)
            default:
                let properties = scalar.properties
                let isMark: Bool
                switch properties.generalCategory {
                case .nonspacingMark, .spacingMark, .enclosingMark: isMark = true
                default: isMark = false
                }
                if properties.isAlphabetic || properties.numericType != nil || isMark {
                    slug.unicodeScalars.append(scalar)
                }
            }
        }
        return slug
    }
}
