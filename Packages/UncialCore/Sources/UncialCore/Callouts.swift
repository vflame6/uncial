import Foundation

/// Obsidian-style callouts: a blockquote whose first line is `[!type]`, optionally `+`/`-` (foldable,
/// open or closed) and a title, becomes a titled, tinted box with the type's icon. The type is
/// case-insensitive; aliases map to Obsidian's default types; an unknown type looks like `note`. No
/// title → the identifier in title case. The content is the rest of the blockquote, nested callouts
/// included. `render` rewrites cmark's HTML; the editor parses the same marker with `marker(in:)`.
public enum Callouts {
    /// The color role a type takes; every theme sets a `--callout-<role>` variable per role.
    public enum Role: String, CaseIterable, Sendable {
        case note, tip, success, question, warning, danger, example, quote
    }

    /// One of Obsidian's default types.
    public struct Kind: Equatable, Sendable {
        public let name: String
        public let aliases: [String]
        public let role: Role
        /// The Lucide icon's name.
        public let icon: String
    }

    public static let kinds: [Kind] = [
        Kind(name: "note", aliases: [], role: .note, icon: "pencil"),
        Kind(name: "abstract", aliases: ["summary", "tldr"], role: .tip, icon: "clipboard-list"),
        Kind(name: "info", aliases: [], role: .note, icon: "info"),
        Kind(name: "todo", aliases: [], role: .note, icon: "circle-check-big"),
        Kind(name: "tip", aliases: ["hint", "important"], role: .tip, icon: "flame"),
        Kind(name: "success", aliases: ["check", "done"], role: .success, icon: "check"),
        Kind(name: "question", aliases: ["help", "faq"], role: .question, icon: "circle-question-mark"),
        Kind(name: "warning", aliases: ["caution", "attention"], role: .warning, icon: "triangle-alert"),
        Kind(name: "failure", aliases: ["fail", "missing"], role: .danger, icon: "x"),
        Kind(name: "danger", aliases: ["error"], role: .danger, icon: "zap"),
        Kind(name: "bug", aliases: [], role: .danger, icon: "bug"),
        Kind(name: "example", aliases: [], role: .example, icon: "list"),
        Kind(name: "quote", aliases: ["cite"], role: .quote, icon: "quote"),
    ]

    private static let kindsByIdentifier: [String: Kind] = {
        var table: [String: Kind] = [:]
        for kind in kinds {
            table[kind.name] = kind
            for alias in kind.aliases {
                table[alias] = kind
            }
        }
        return table
    }()

    /// The default type an identifier names (aliases mapped, case ignored), or the lowercased
    /// identifier when it names none: what `data-callout` carries.
    public static func type(for identifier: String) -> String {
        let lowered = identifier.lowercased()
        return kindsByIdentifier[lowered]?.name ?? lowered
    }

    /// The default kind a type is drawn as; unknown types are drawn as `note`.
    public static func kind(for type: String) -> Kind {
        kindsByIdentifier[type.lowercased()] ?? kinds[0]
    }

    public static func role(for type: String) -> Role {
        kind(for: type).role
    }

    /// The type's icon as 24 × 24 SVG with `stroke="currentColor"`.
    public static func icon(for type: String) -> String {
        icons[kind(for: type).icon] ?? icons["pencil"]!
    }

    /// The chevron of a foldable callout's title.
    public static var foldIcon: String {
        icons["chevron-right"]!
    }

    /// The identifier in title case: "Note" for `note` and `NOTE`.
    public static func defaultTitle(for identifier: String) -> String {
        let lowered = identifier.lowercased()
        return lowered.prefix(1).uppercased() + lowered.dropFirst()
    }

    public enum Fold: Equatable, Sendable {
        case open, closed
    }

    /// A `[!type]` marker at the start of a line.
    public struct Marker: Equatable, Sendable {
        /// The identifier as written.
        public let identifier: String
        /// `Callouts.type(for:)` of the identifier.
        public let type: String
        public let fold: Fold?
        /// The UTF-16 length of the marker, its fold sign and the whitespace after it.
        public let length: Int
        /// The rest of the line, trailing whitespace trimmed; empty when the callout has no title.
        public let title: String

        public var defaultTitle: String {
            Callouts.defaultTitle(for: identifier)
        }
    }

    /// `[!identifier]`, an optional `+`/`-`, then whitespace or the end of the line.
    private static let markerPattern = try! NSRegularExpression(pattern: #"^\[!([A-Za-z0-9_-]+)\]([+-])?(?:[ \t]+|$)"#)

    /// The marker `line` starts with, if any.
    public static func marker(in line: String) -> Marker? {
        let text = line as NSString
        guard let match = markerPattern.firstMatch(in: line, range: NSRange(location: 0, length: text.length)) else { return nil }
        let identifier = text.substring(with: match.range(at: 1))
        let fold: Fold? = switch match.range(at: 2).location == NSNotFound ? "" : text.substring(with: match.range(at: 2)) {
        case "+": .open
        case "-": .closed
        default: nil
        }
        let title = text.substring(from: match.range.length).trimmingCharacters(in: .whitespaces)
        return Marker(identifier: identifier, type: type(for: identifier), fold: fold, length: match.range.length, title: title)
    }

    // MARK: HTML

    private static let blockquoteStart = try! NSRegularExpression(pattern: #"<blockquote(\s[^>]*)?>\n<p(\s[^>]*)?>"#)
    private static let blockquoteTag = try! NSRegularExpression(pattern: #"<blockquote[\s>]|</blockquote>"#)
    private static let sourcePosition = try! NSRegularExpression(pattern: #"^\sdata-sourcepos="(\d+):(\d+)-(\d+):(\d+)"$"#)

    /// Rewrites every callout blockquote in cmark's `html` (see the type's notes). The first
    /// paragraph is split at its first soft break, the rest keeping a `data-sourcepos` moved one line
    /// down; the container carries the blockquote's. Nested callouts are rewritten inside.
    public static func render(_ html: String) -> String {
        guard html.contains("[!") else { return html }
        let source = html as NSString
        return rewrite(source, in: NSRange(location: 0, length: source.length))
    }

    private static func rewrite(_ source: NSString, in range: NSRange) -> String {
        var output = ""
        var cursor = range.location
        let end = NSMaxRange(range)
        while cursor < end {
            guard let match = blockquoteStart.firstMatch(in: source as String, range: NSRange(location: cursor, length: end - cursor)) else { break }
            let contentStart = NSMaxRange(match.range)
            let lineEnd = min(source.range(of: "\n", range: NSRange(location: contentStart, length: end - contentStart)).location,
                              source.range(of: "</p>", range: NSRange(location: contentStart, length: end - contentStart)).location)
            guard lineEnd != NSNotFound, let marker = marker(in: source.substring(with: NSRange(location: contentStart, length: lineEnd - contentStart))),
                  let closing = closingTag(after: contentStart, before: end, in: source) else {
                output += source.substring(with: NSRange(location: cursor, length: NSMaxRange(match.range) - cursor))
                cursor = NSMaxRange(match.range)
                continue
            }
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let quoteAttributes = match.range(at: 1).location == NSNotFound ? "" : source.substring(with: match.range(at: 1))
            let paragraphAttributes = match.range(at: 2).location == NSNotFound ? "" : source.substring(with: match.range(at: 2))
            let paragraphEnd = source.range(of: "</p>", range: NSRange(location: lineEnd, length: closing.location - lineEnd))
            var rest = ""
            if paragraphEnd.location != NSNotFound, lineEnd < paragraphEnd.location {
                rest = source.substring(with: NSRange(location: lineEnd + 1, length: paragraphEnd.location - lineEnd - 1))
            }
            var remainingStart = paragraphEnd.location == NSNotFound ? closing.location : NSMaxRange(paragraphEnd)
            if remainingStart < closing.location, source.character(at: remainingStart) == 0x0A {
                remainingStart += 1
            }
            let remaining = rewrite(source, in: NSRange(location: remainingStart, length: closing.location - remainingStart))
            var title = marker.title
            if title.hasSuffix("<br />") {
                title = String(title.dropLast(6)).trimmingCharacters(in: .whitespaces)
            }
            var content = ""
            if !rest.isEmpty {
                content += "<p\(shiftedDown(paragraphAttributes))>\(rest)</p>\n"
            }
            content += remaining
            output += callout(marker: marker, title: title.isEmpty ? marker.defaultTitle : title, content: content, attributes: quoteAttributes)
            cursor = NSMaxRange(closing)
        }
        output += source.substring(with: NSRange(location: cursor, length: end - cursor))
        return output
    }

    private static func callout(marker: Marker, title: String, content: String, attributes: String) -> String {
        let tag = marker.fold == nil ? "div" : "details"
        let titleTag = marker.fold == nil ? "p" : "summary"
        var html = "<\(tag) class=\"callout\" data-callout=\"\(marker.type)\"\(marker.fold == .open ? " open" : "")\(attributes)>\n"
        html += "<\(titleTag) class=\"callout-title\"><span class=\"callout-icon\">\(icon(for: marker.type))</span><span class=\"callout-title-text\">\(title)</span>"
        if marker.fold != nil {
            html += "<span class=\"callout-fold\">\(foldIcon)</span>"
        }
        html += "</\(titleTag)>\n"
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            html += "<div class=\"callout-content\">\n\(content)\(content.hasSuffix("\n") ? "" : "\n")</div>\n"
        }
        return html + "</\(tag)>"
    }

    /// The `</blockquote>` that closes the blockquote whose content starts at `start`.
    private static func closingTag(after start: Int, before end: Int, in source: NSString) -> NSRange? {
        var depth = 1
        for match in blockquoteTag.matches(in: source as String, range: NSRange(location: start, length: end - start)) {
            if source.substring(with: match.range).hasPrefix("</") {
                depth -= 1
                if depth == 0 { return match.range }
            } else {
                depth += 1
            }
        }
        return nil
    }

    /// A paragraph's `data-sourcepos` starting one line later (its first line became the title).
    private static func shiftedDown(_ attributes: String) -> String {
        guard let match = sourcePosition.firstMatch(in: attributes, range: NSRange(location: 0, length: (attributes as NSString).length)) else { return attributes }
        let text = attributes as NSString
        let numbers = (1...4).map { Int(text.substring(with: match.range(at: $0))) ?? 0 }
        return " data-sourcepos=\"\(numbers[0] + 1):1-\(numbers[2]):\(numbers[3])\""
    }
}
