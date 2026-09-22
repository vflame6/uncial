import Foundation

/// Keeps a rendered page off the internet while remote content is off (`AppSettings.loadRemoteContent`,
/// shared with Quick Look): on media and resource elements, `src`, `srcset`, `poster`, `data` and
/// `href` values that point at the web become `data-blocked-…` attributes, `url(…)` to the web in a
/// `style` attribute becomes `none`, and a `<meta http-equiv>` (refresh) loses its power. Links stay
/// as they are: following one is the reader's decision. The app's web view blocks such loads on its
/// own as well; this pass is what protects Quick Look, which renders the HTML elsewhere.
public enum RemoteContent {
    private static let resourceTag = try! NSRegularExpression(
        pattern: #"<(?:img|source|video|audio|track|embed|object|iframe|frame|link|image|use|input|meta)\b[^>]*>"#,
        options: .caseInsensitive)
    private static let resourceAttribute = try! NSRegularExpression(
        pattern: #"(?<=\s)(src|srcset|poster|data|href|xlink:href)(\s*=\s*)(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
        options: .caseInsensitive)
    private static let metaEquiv = try! NSRegularExpression(pattern: #"(?<=\s)http-equiv(?=\s*=)"#, options: .caseInsensitive)
    private static let styleAttribute = try! NSRegularExpression(pattern: #"(?<=\s)style\s*=\s*(?:"[^"]*"|'[^']*')"#, options: .caseInsensitive)
    private static let styleURL = try! NSRegularExpression(pattern: #"url\(\s*(?:&quot;|&#39;|['"])?\s*(?:https?:|ftp:|wss?:)?//[^)]*\)"#, options: .caseInsensitive)
    private static let remoteURL = try! NSRegularExpression(pattern: #"^\s*(?:https?:|ftp:|wss?:|//)"#, options: .caseInsensitive)

    /// `html` with every reference to the web on a resource element neutralized.
    public static func block(in html: String) -> String {
        guard html.contains("<") else { return html }
        var output = replacing(resourceTag, in: html) { tag in
            var tag = replacing(resourceAttribute, in: tag) { attribute, match, source in
                let name = source.substring(with: match.range(at: 1))
                let value = [3, 4, 5].map(match.range(at:)).first { $0.location != NSNotFound }.map(source.substring(with:)) ?? ""
                guard isRemote(value, list: name.lowercased() == "srcset") else { return attribute }
                return "data-blocked-" + attribute
            }
            if tag.lowercased().hasPrefix("<meta") {
                tag = metaEquiv.stringByReplacingMatches(in: tag, range: NSRange(location: 0, length: (tag as NSString).length), withTemplate: "data-blocked-http-equiv")
            }
            return tag
        }
        guard output.contains("url(") || output.contains("URL(") else { return output }
        output = replacing(styleAttribute, in: output) { attribute in
            styleURL.stringByReplacingMatches(in: attribute, range: NSRange(location: 0, length: (attribute as NSString).length), withTemplate: "none")
        }
        return output
    }

    /// Whether `value` (an attribute's text) points at the web; a `list` (srcset) does if any candidate does.
    static func isRemote(_ value: String, list: Bool = false) -> Bool {
        let candidates = list ? value.split(separator: ",").map(String.init) : [value]
        return candidates.contains { candidate in
            remoteURL.firstMatch(in: candidate, range: NSRange(location: 0, length: (candidate as NSString).length)) != nil
        }
    }

    private static func replacing(_ regex: NSRegularExpression, in text: String, _ transform: (String) -> String) -> String {
        replacing(regex, in: text) { matched, _, _ in transform(matched) }
    }

    private static func replacing(_ regex: NSRegularExpression, in text: String, _ transform: (String, NSTextCheckingResult, NSString) -> String) -> String {
        let source = text as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += transform(source.substring(with: match.range), match, source)
            cursor = NSMaxRange(match.range)
        }
        output += source.substring(from: cursor)
        return output
    }
}
