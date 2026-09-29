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

    /// `html` with every `<meta http-equiv>` renamed as `block(in:)` renames it (`data-blocked-http-equiv`),
    /// links and resources untouched: a page leaving the app (File ▸ Export) is opened by browsers,
    /// which follow a refresh, or take a cookie or policy header, the app's web view never obeys. Each
    /// meta tag is read as a browser's tokenizer reads it (`attributeNames(in:from:)`): a `[^>]*` pattern
    /// stopped at a `>` inside a quoted value and missed the `http-equiv` after it.
    public static func disarmMetaEquiv(in html: String) -> String {
        guard html.range(of: "http-equiv", options: .caseInsensitive) != nil else { return html }
        let bytes = Array(html.utf8)
        var names: [Range<Int>] = []
        var index = 0
        while index < bytes.count {
            guard startsMetaTag(bytes, at: index) else {
                index += 1
                continue
            }
            let (found, end) = attributeNames(in: bytes, from: index + 5)
            names += found.filter { lowercased(bytes[$0]) == Array("http-equiv".utf8) }
            index = end
        }
        guard !names.isEmpty else { return html }
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count + names.count * 13)
        var cursor = 0
        for name in names {
            output += bytes[cursor..<name.lowerBound]
            output += Array("data-blocked-http-equiv".utf8)
            cursor = name.upperBound
        }
        output += bytes[cursor...]
        return String(decoding: output, as: UTF8.self)
    }

    /// Whether a `<meta` tag starts at `index`: the name in any case, then whitespace, `/` or `>` (or the end).
    private static func startsMetaTag(_ bytes: [UInt8], at index: Int) -> Bool {
        guard bytes[index] == UInt8(ascii: "<"), index + 5 <= bytes.count,
              lowercased(bytes[(index + 1)..<(index + 5)]) == Array("meta".utf8) else { return false }
        return index + 5 == bytes.count || isTagSpace(bytes[index + 5]) || bytes[index + 5] == UInt8(ascii: "/") || bytes[index + 5] == UInt8(ascii: ">")
    }

    /// The byte ranges of the attribute names of the start tag whose name ends at `start`, read as the HTML
    /// tokenizer reads them: a name runs to whitespace, `/`, `>` or `=`; a value in quotes runs to the same
    /// quote whatever it holds (`>` included), an unquoted one to whitespace or `>` (quotes included).
    /// Also the index just past the tag's `>`, or the end of the text.
    static func attributeNames(in bytes: [UInt8], from start: Int) -> (names: [Range<Int>], end: Int) {
        let slash = UInt8(ascii: "/"), greater = UInt8(ascii: ">"), equals = UInt8(ascii: "=")
        var names: [Range<Int>] = []
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if isTagSpace(byte) || byte == slash {
                index += 1
                continue
            }
            if byte == greater { return (names, index + 1) }
            let nameStart = index
            index += 1
            while index < bytes.count, !isTagSpace(bytes[index]), ![slash, greater, equals].contains(bytes[index]) { index += 1 }
            names.append(nameStart..<index)
            while index < bytes.count, isTagSpace(bytes[index]) { index += 1 }
            guard index < bytes.count, bytes[index] == equals else { continue }
            index += 1
            while index < bytes.count, isTagSpace(bytes[index]) { index += 1 }
            guard index < bytes.count else { break }
            let quote = bytes[index]
            if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") {
                index += 1
                while index < bytes.count, bytes[index] != quote { index += 1 }
                index += 1
            } else if quote == greater {
                return (names, index + 1)
            } else {
                while index < bytes.count, !isTagSpace(bytes[index]), bytes[index] != greater { index += 1 }
            }
        }
        return (names, bytes.count)
    }

    /// HTML's whitespace in tags (tab, line feed, form feed, carriage return, space).
    private static func isTagSpace(_ byte: UInt8) -> Bool {
        byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D || byte == 0x20
    }

    private static func lowercased(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        bytes.map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }
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
