import Foundation

/// Keeps a rendered page off the internet while remote content is off (`AppSettings.loadRemoteContent`,
/// shared with Quick Look): on media and resource elements, `src`, `srcset`, `poster`, `data`, `href`,
/// `background` and SMIL `to`/`from`/`values` that point at the web become `data-blocked-…`
/// attributes, `url(…)` to the web in a `style` attribute becomes `none` (and a style that still
/// names the web once decoded loses the attribute), and a `<meta http-equiv>` (refresh) loses its
/// power. Values are judged the way the browser reads them: character references and CSS escapes
/// decoded, tabs, line breaks and leading controls dropped. Links stay as they are: following one
/// is the reader's decision. The app's web view blocks such loads on its own as well, and Quick
/// Look's page carries `HTMLDocument.offlinePolicy`; this pass is the layer under both.
public enum RemoteContent {
    private static let resourceTag = try! NSRegularExpression(
        pattern: #"<(?:img|source|video|audio|track|embed|object|iframe|frame|link|image|use|input|meta|feimage|base|body|table|thead|tbody|tfoot|tr|td|th|set|animate)\b[^>]*>"#,
        options: .caseInsensitive)
    /// An attribute begins after whitespace, a `/` or the quote that closed the one before it.
    private static let resourceAttribute = try! NSRegularExpression(
        pattern: #"(?<=[\s/"'])(src|srcset|imagesrcset|poster|data|href|xlink:href|background|to|from|values)(\s*=\s*)(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
        options: .caseInsensitive)
    private static let metaEquiv = try! NSRegularExpression(pattern: #"(?<=[\s/"'])http-equiv(?=\s*=)"#, options: .caseInsensitive)
    private static let styleAttribute = try! NSRegularExpression(
        pattern: #"(?<=[\s/"'])style(\s*=\s*)(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#, options: .caseInsensitive)
    private static let styleURL = try! NSRegularExpression(pattern: #"url\(\s*(?:&quot;|&#39;|['"])?\s*(?:https?:|ftp:|wss?:)?//[^)]*\)"#, options: .caseInsensitive)
    private static let remoteURL = try! NSRegularExpression(pattern: #"^(?:https?:|ftp:|wss?:|[/\\]{2})"#, options: .caseInsensitive)
    private static let characterReference = try! NSRegularExpression(pattern: #"&(?:#[xX]([0-9a-fA-F]+)|#([0-9]+)|([A-Za-z]+));?"#)
    private static let cssURL = try! NSRegularExpression(pattern: #"url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*))\s*\)"#, options: .caseInsensitive)
    private static let cssString = try! NSRegularExpression(pattern: #""([^"]*)"|'([^']*)'"#)
    /// The named references a URL can be spelled with.
    private static let namedReferences: [String: String] = [
        "colon": ":", "sol": "/", "bsol": "\\", "Tab": "\t", "NewLine": "\n", "period": ".", "lpar": "(",
        "rpar": ")", "amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "nbsp": "\u{A0}",
    ]

    /// `html` with every reference to the web on a resource element neutralized.
    public static func block(in html: String) -> String {
        guard html.contains("<") else { return html }
        var output = replacing(resourceTag, in: html) { tag in
            var tag = replacing(resourceAttribute, in: tag) { attribute, match, source in
                let name = source.substring(with: match.range(at: 1)).lowercased()
                let value = [3, 4, 5].map(match.range(at:)).first { $0.location != NSNotFound }.map(source.substring(with:)) ?? ""
                let separator: Character? = name == "srcset" || name == "imagesrcset" ? "," : name == "values" ? ";" : nil
                guard isRemote(value, separatedBy: separator) else { return attribute }
                return "data-blocked-" + attribute
            }
            if tag.lowercased().hasPrefix("<meta") {
                tag = metaEquiv.stringByReplacingMatches(in: tag, range: NSRange(location: 0, length: (tag as NSString).length), withTemplate: "data-blocked-http-equiv")
            }
            return tag
        }
        guard output.range(of: "style", options: .caseInsensitive) != nil else { return output }
        output = replacing(styleAttribute, in: output) { attribute, match, source in
            let disarmed = styleURL.stringByReplacingMatches(in: attribute, range: NSRange(location: 0, length: (attribute as NSString).length), withTemplate: "none")
            let value = [2, 3, 4].map(match.range(at:)).first { $0.location != NSNotFound }.map(source.substring(with:)) ?? ""
            let rest = styleURL.stringByReplacingMatches(in: value, range: NSRange(location: 0, length: (value as NSString).length), withTemplate: "none")
            return styleIsRemote(rest) ? "data-blocked-" + attribute : disarmed
        }
        return output
    }

    /// Whether `value` (an attribute's text) points at the web; a list (`srcset`, SMIL `values`)
    /// does if any candidate does.
    static func isRemote(_ value: String, separatedBy separator: Character? = nil) -> Bool {
        let parsed = String(String.UnicodeScalarView(decodingReferences(value).unicodeScalars.filter { !["\t", "\n", "\r"].contains($0) }))
        let candidates = separator.map { parsed.split(separator: $0).map(String.init) } ?? [parsed]
        return candidates.contains { candidate in
            let trimmed = String(String.UnicodeScalarView(candidate.unicodeScalars.drop { $0.value <= 0x20 }))
            return remoteURL.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil
        }
    }

    /// Whether a style attribute's text still names the web once decoded as the browser decodes it:
    /// character references, then CSS escapes; `url()` arguments and plain strings (`image-set()`).
    static func styleIsRemote(_ value: String) -> Bool {
        let css = cssUnescaped(decodingReferences(value)) as NSString
        var withoutURLs = css as String
        for match in cssURL.matches(in: css as String, range: NSRange(location: 0, length: css.length)).reversed() {
            let argument = [1, 2, 3].map(match.range(at:)).first { $0.location != NSNotFound }.map(css.substring(with:)) ?? ""
            if isRemote(argument) { return true }
            withoutURLs = (withoutURLs as NSString).replacingCharacters(in: match.range, with: "none")
        }
        let rest = withoutURLs as NSString
        return cssString.matches(in: withoutURLs, range: NSRange(location: 0, length: rest.length)).contains { match in
            let string = [1, 2].map(match.range(at:)).first { $0.location != NSNotFound }.map(rest.substring(with:)) ?? ""
            return isRemote(string)
        }
    }

    /// Numeric character references and the named ones a URL can be spelled with, decoded.
    static func decodingReferences(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let source = text as NSString
        var output = ""
        var cursor = 0
        for match in characterReference.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let replacement: String?
            if match.range(at: 1).location != NSNotFound {
                replacement = UInt32(source.substring(with: match.range(at: 1)), radix: 16).map(scalarText)
            } else if match.range(at: 2).location != NSNotFound {
                replacement = UInt32(source.substring(with: match.range(at: 2))).map(scalarText)
            } else {
                replacement = namedReferences[source.substring(with: match.range(at: 3))]
            }
            guard let replacement else { continue }
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)) + replacement
            cursor = NSMaxRange(match.range)
        }
        output += source.substring(from: cursor)
        return output
    }

    private static func scalarText(_ value: UInt32) -> String {
        String(Unicode.Scalar(value).map(Character.init) ?? "\u{FFFD}")
    }

    /// CSS escapes decoded: a backslash and up to six hex digits (plus one whitespace after them),
    /// or a backslash and any other character, which stands for itself.
    static func cssUnescaped(_ text: String) -> String {
        guard text.contains("\\") else { return text }
        var output = String.UnicodeScalarView()
        var scalars = text.unicodeScalars[...]
        while let scalar = scalars.popFirst() {
            guard scalar == "\\", let next = scalars.first else {
                output.append(scalar)
                continue
            }
            var hex = ""
            while hex.count < 6, let digit = scalars.first, digit.properties.isASCIIHexDigit {
                hex.unicodeScalars.append(digit)
                scalars.removeFirst()
            }
            if hex.isEmpty {
                output.append(next)
                scalars.removeFirst()
            } else {
                output.append(UInt32(hex, radix: 16).flatMap(Unicode.Scalar.init) ?? "\u{FFFD}")
                if let space = scalars.first, [" ", "\t", "\n", "\r", "\u{0C}"].contains(space) { scalars.removeFirst() }
            }
        }
        return String(output)
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
