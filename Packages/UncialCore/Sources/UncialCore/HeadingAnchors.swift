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
        // github-slugger: every id given out is recorded, and a taken one counts on from its base until
        // one is free (`A`, `A`, `A-1` are a, a-1, a-1-1). Ids a heading brings are taken too.
        var used: [String: Int] = [:]
        var output = ""
        var cursor = 0
        for match in heading.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let level = source.substring(with: match.range(at: 1))
            let attributes = match.range(at: 2).location == NSNotFound ? "" : source.substring(with: match.range(at: 2))
            let inner = source.substring(with: match.range(at: 3))
            let attributeRange = NSRange(location: 0, length: (attributes as NSString).length)
            if let existing = idAttribute.firstMatch(in: attributes, range: attributeRange) {
                if let value = Self.value(after: existing, in: attributes) { used[value] = used[value] ?? 0 }
                output += source.substring(with: match.range)
            } else {
                let base = slug(for: inner)
                var id = base
                while let count = used[base], used[id] != nil {
                    used[base] = count + 1
                    id = "\(base)-\(count + 1)"
                }
                used[id] = 0
                output += "<h\(level) id=\"\(id)\"\(attributes)>\(inner)</h\(level)>"
            }
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        return output
    }

    /// The quoted value of the attribute whose `name=` `match` found.
    private static func value(after match: NSTextCheckingResult, in attributes: String) -> String? {
        let rest = (attributes as NSString).substring(from: NSMaxRange(match.range)).drop { $0 == " " }
        guard let quote = rest.first, quote == "\"" || quote == "'" else { return nil }
        return rest.dropFirst().prefix { $0 != quote }.description
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
