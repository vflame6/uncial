import Foundation
import JavaScriptCore

/// Fenced code → highlighted HTML through highlight.js (bundled, BSD-3-Clause, plus the Apache-2.0
/// COBOL grammar) in a JavaScriptCore context, so the page needs no script and Quick Look shows the
/// same colors. `scripts/build-highlight.sh` lists the grammars and fence aliases in the bundle. The
/// output is `<span class="hljs-…">` runs that never cross a line break, so `SourcePositions` can
/// wrap every code line and the editor can color line by line (`tokens(in:language:)`). `Scope` is
/// the palette role of a highlight.js class: the stylesheet's `--code-…` variables and the editor's
/// `SyntaxPalette` colors are named after it.
public enum CodeHighlighter {
    /// The roles highlighted code is drawn in.
    public enum Scope: String, CaseIterable, Sendable {
        case comment, keyword, string, number, type, function, variable, meta, tag, addition, deletion
    }

    /// One highlighted run of a code string: `range` in UTF-16 units, never crossing a line break.
    public struct Token: Equatable, Sendable {
        public let range: NSRange
        public let scope: Scope

        public init(range: NSRange, scope: Scope) {
            self.range = range
            self.scope = scope
        }
    }

    /// A highlight.js instance, created on first use. JavaScriptCore serializes calls on a context; the
    /// lock keeps whole highlight calls from interleaving on top of that. Known languages have a lock
    /// of their own, so a cached answer never waits behind a highlight.
    private final class Engine: @unchecked Sendable {
        private let lock = NSLock()
        private let context: JSContext
        private let hljs: JSValue
        private let knownLock = NSLock()
        private var known: [String: Bool] = [:]

        init?() {
            guard let url = Bundle.module.url(forResource: "highlight.min", withExtension: "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8),
                  let context = JSContext() else { return nil }
            context.exceptionHandler = { context, exception in context?.exception = exception }
            context.evaluateScript("var console = globalThis.console || { log: function () {}, warn: function () {}, error: function () {} };")
            context.evaluateScript(source)
            guard let hljs = context.objectForKeyedSubscript("hljs"), hljs.isObject else { return nil }
            self.context = context
            self.hljs = hljs
        }

        func supports(_ language: String) -> Bool {
            if let answer = knownLock.withLock({ known[language] }) { return answer }
            lock.lock()
            defer { lock.unlock() }
            context.exception = nil
            let grammar = hljs.invokeMethod("getLanguage", withArguments: [language])
            let supported = context.exception == nil && grammar.map { !$0.isUndefined && !$0.isNull } == true
            knownLock.withLock { known[language] = supported }
            return supported
        }

        /// highlight.js's HTML for `code`, or nil when the library throws.
        func highlight(_ code: String, language: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            context.exception = nil
            let options: [String: Any] = ["language": language, "ignoreIllegals": true]
            guard let result = hljs.invokeMethod("highlight", withArguments: [code, options]), context.exception == nil,
                  let value = result.objectForKeyedSubscript("value"), value.isString else { return nil }
            return value.toString()
        }
    }

    /// The answer per language and source (misses too), so re-rendering while typing does not
    /// re-highlight every block in the document, and the editor's coloring shares the page's work.
    /// Least recently used out, beyond `capacity` entries or `byteLimit` bytes of keys and answers
    /// (PERF-4, 2026-09-26: a 64-entry FIFO missed on every pass once a document had more blocks,
    /// 50–90 ms of JavaScript per keystroke).
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: (value: String?, used: Int)] = [:]
        private var clock = 0
        private var bytes = 0
        private let capacity = 1024
        private let byteLimit = 16 << 20

        func contains(_ key: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return entries[key] != nil
        }

        func value(for key: String) -> String?? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[key] else { return nil }
            clock += 1
            entries[key]?.used = clock
            return .some(entry.value)
        }

        func set(_ value: String?, for key: String) {
            lock.lock()
            defer { lock.unlock() }
            clock += 1
            if let old = entries.updateValue((value, clock), forKey: key) {
                bytes -= Self.size(key, old.value)
            }
            bytes += Self.size(key, value)
            while entries.count > capacity || (bytes > byteLimit && entries.count > 1) {
                guard let oldest = entries.min(by: { $0.value.used < $1.value.used }) else { break }
                entries.removeValue(forKey: oldest.key)
                bytes -= Self.size(oldest.key, oldest.value.value)
            }
        }

        private static func size(_ key: String, _ value: String?) -> Int {
            key.utf8.count + (value?.utf8.count ?? 0)
        }
    }

    /// Page renders (off the main thread, and Quick Look's) and the editor (on the main thread) have an
    /// engine each: the editor never waits for a page render to finish a block (STAB-1, 2026-09-26: one
    /// slow block froze every window for seconds).
    private static let pageEngine = Engine()
    private static let editorEngine = Engine()
    private static let cache = Cache()

    /// A block with a line longer than this, or longer in all than `maxCodeLength` (UTF-16 units), stays
    /// plain: highlight.js's work on a line can grow with the square of its length (its markdown grammar
    /// took 10.8 s for one line of 32,000 `[`), and JavaScriptCore cannot interrupt a script.
    static let maxLineLength = 1_000
    static let maxCodeLength = 64 * 1024
    /// The code a page highlights in all; the blocks after it stay as cmark wrote them.
    static let pageBudget = 512 * 1024

    /// Whether highlighting `code` in `language` would come from the cache. For tests.
    static func isCached(_ code: String, language: String) -> Bool {
        cache.contains(key(for: code, language: normalized(language)))
    }


    private static let fence = try! NSRegularExpression(pattern: #"<pre(?:\s+data-sourcepos="[^"]*")?[^>]*><code class="language-([^"\s]+)">([\s\S]*?)</code></pre>"#)
    private static let emptySpan = try! NSRegularExpression(pattern: #"<span[^>]*></span>"#)

    /// Whether the bundle has a grammar (or alias) under `language`; names are matched case-insensitively.
    /// Asked on the main thread by the editor, so it goes to the editor's engine.
    public static func supports(_ language: String) -> Bool {
        let name = normalized(language)
        guard !name.isEmpty else { return false }
        return editorEngine?.supports(name) ?? false
    }

    /// Whether highlighting `code` stays within `maxCodeLength` and `maxLineLength`.
    static func isWithinLimits(_ code: String) -> Bool {
        let units = code.utf16
        guard units.count <= maxCodeLength else { return false }
        var line = 0
        for unit in units {
            if unit == 0x0A || unit == 0x0D {
                line = 0
            } else {
                line += 1
                if line > maxLineLength { return false }
            }
        }
        return true
    }

    /// Replaces the content of every `<pre><code class="language-…">` whose language the bundle knows
    /// with highlight.js's spans, balanced per line, until `budget` characters of code are highlighted;
    /// other blocks stay as cmark wrote them.
    static func render(_ html: String, budget: Int = pageBudget) -> String {
        guard html.contains("<code class=\"language-") else { return html }
        let text = html as NSString
        var result = ""
        var position = 0
        var used = 0
        for match in fence.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            result += text.substring(with: NSRange(location: position, length: match.range.location - position))
            let language = HTMLEscaping.unescape(text.substring(with: match.range(at: 1)))
            let code = HTMLEscaping.unescape(text.substring(with: match.range(at: 2)))
            let length = code.utf16.count
            if used + length <= budget, let highlighted = self.html(for: code, language: language, engine: pageEngine) {
                used += length
                let opening = text.substring(with: NSRange(location: match.range.location, length: match.range(at: 2).location - match.range.location))
                result += opening + highlighted + "</code></pre>"
            } else {
                result += text.substring(with: match.range)
            }
            position = NSMaxRange(match.range)
        }
        result += text.substring(from: position)
        return result
    }

    /// `code` as highlight.js HTML (entities escaped, `<span class="hljs-…">` runs that never cross a
    /// line break), or nil for a language the bundle does not know and for code over the limits.
    /// Cached per language and source, for the page and the editor alike.
    public static func html(for code: String, language: String) -> String? {
        html(for: code, language: language, engine: pageEngine)
    }

    /// cmark's code ends with a newline and the editor's does not: one entry answers both.
    private static func key(for code: String, language name: String) -> String {
        name + "\u{0}" + (code.hasSuffix("\n") ? String(code.dropLast()) : code)
    }

    private static func html(for code: String, language: String, engine: Engine?) -> String? {
        let name = normalized(language)
        guard let engine, !name.isEmpty, isWithinLimits(code), engine.supports(name) else { return nil }
        let newline = code.hasSuffix("\n")
        let key = key(for: code, language: name)
        let highlighted: String?
        if let cached = cache.value(for: key) {
            highlighted = cached
        } else {
            highlighted = engine.highlight(newline ? String(code.dropLast()) : code, language: name).map(balanced)
            cache.set(highlighted, for: key)
        }
        return newline ? highlighted.map { $0 + "\n" } : highlighted
    }

    /// The highlighted runs of `code` with their palette roles, in order, for an editor that colors
    /// text instead of HTML: ranges are UTF-16 offsets into `code`, none crosses a line break, and
    /// text whose innermost class has no role (punctuation, interpolation, parameters, …) is left out.
    public static func tokens(in code: String, language: String) -> [Token] {
        guard let html = html(for: code, language: language, engine: editorEngine) else { return [] }
        var tokens: [Token] = []
        var stack: [Scope?] = []
        var offset = 0
        let bytes = Array(html.utf8)
        var index = 0
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "<"), let close = bytes[index...].firstIndex(of: UInt8(ascii: ">")) {
                if index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "/") {
                    if !stack.isEmpty { stack.removeLast() }
                } else {
                    stack.append(scope(forClasses: classes(ofTag: bytes[index...close])))
                }
                index = close + 1
                continue
            }
            let end = bytes[index...].firstIndex(of: UInt8(ascii: "<")) ?? bytes.count
            let run = HTMLEscaping.unescape(String(decoding: bytes[index..<end], as: UTF8.self))
            let length = run.utf16.count
            if let scope = stack.last ?? nil, length > 0 {
                if let last = tokens.last, last.scope == scope, NSMaxRange(last.range) == offset {
                    tokens[tokens.count - 1] = Token(range: NSRange(location: last.range.location, length: last.range.length + length), scope: scope)
                } else {
                    tokens.append(Token(range: NSRange(location: offset, length: length), scope: scope))
                }
            }
            offset += length
            index = end
        }
        return tokens
    }

    /// The palette role of a highlight.js class list (`hljs-keyword`, `hljs-title class_`, …); nil
    /// for classes drawn in the plain code color (`hljs-subst`, `hljs-params`, `hljs-punctuation`,
    /// the `hljs-tag` wrapper around an element, …). Mirrors the `.hljs-…` rules of `Stylesheet`.
    static func scope(forClasses classes: String) -> Scope? {
        let names = classes.split(separator: " ")
        guard let main = names.first(where: { $0.hasPrefix("hljs-") })?.dropFirst(5) else { return nil }
        switch main {
        case "comment", "quote": return .comment
        case "keyword", "doctag", "template-tag": return .keyword
        case "string", "regexp", "char", "code", "formula": return .string
        case "number", "literal", "symbol", "bullet": return .number
        case "type", "built_in": return .type
        case "title": return names.contains("class_") ? .type : .function
        case "section": return .function
        case "variable", "template-variable", "attr", "attribute", "property", "selector-attr", "selector-pseudo": return .variable
        case "meta": return .meta
        case "name", "selector-tag", "selector-id", "selector-class": return .tag
        case "addition": return .addition
        case "deletion": return .deletion
        default: return nil
        }
    }

    /// Closes every open span before a line break and reopens it after, so no span crosses a line
    /// (block comments and multi-line strings do in highlight.js's output). Spans left empty by that go.
    static func balanced(_ html: String) -> String {
        guard html.contains("\n"), html.contains("<span") else { return html }
        let bytes = Array(html.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count + 256)
        var stack: [ArraySlice<UInt8>] = []
        let closing = Array("</span>".utf8)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "<"), let close = bytes[index...].firstIndex(of: UInt8(ascii: ">")) {
                let tag = bytes[index...close]
                if index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "/") {
                    if !stack.isEmpty { stack.removeLast() }
                } else {
                    stack.append(tag)
                }
                output.append(contentsOf: tag)
                index = close + 1
            } else if byte == UInt8(ascii: "\n"), !stack.isEmpty {
                for _ in stack { output.append(contentsOf: closing) }
                output.append(byte)
                for tag in stack { output.append(contentsOf: tag) }
                index += 1
            } else {
                output.append(byte)
                index += 1
            }
        }
        let joined = String(decoding: output, as: UTF8.self)
        return emptySpan.stringByReplacingMatches(in: joined, range: NSRange(location: 0, length: (joined as NSString).length), withTemplate: "")
    }

    private static func classes(ofTag tag: ArraySlice<UInt8>) -> String {
        let text = String(decoding: tag, as: UTF8.self)
        guard let start = text.range(of: "class=\""), let end = text[start.upperBound...].firstIndex(of: "\"") else { return "" }
        return String(text[start.upperBound..<end])
    }

    private static func normalized(_ language: String) -> String {
        language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
