import Foundation
import JavaScriptCore
import cmark_gfm

/// A diagram drawn ahead of time by the official mermaid.js (in the app's hidden web view): the SVG in
/// the theme's light colors and again in its dark ones.
public struct PreRenderedDiagram: Equatable, Sendable {
    public let light: String
    public let dark: String

    public init(light: String, dark: String) {
        self.light = light
        self.dark = dark
    }
}

/// Mermaid fences → inline SVG. beautiful-mermaid (bundled, MIT; elkjs inside, EPL-2.0) runs in a
/// JavaScriptCore context and draws flowcharts, state, sequence, class and ER diagrams and XY charts
/// with colors that are CSS variables, so those follow the theme live. Every other diagram type
/// (pie, gantt, mindmap, timeline, …) needs a browser DOM, so the callers draw it with the official
/// mermaid.js in a hidden web view and hand the result in as `PreRenderedDiagram`s; a fence neither
/// engine accepts stays a code block. The page never runs a script, so Quick Look renders it all.
public enum MermaidRenderer {
    /// One beautiful-mermaid instance per process, created on the first fence. The bundle expects a
    /// browser: elkjs wants `window`, timers (never waited for: the library flushes them itself) and `atob`.
    private final class Engine: @unchecked Sendable {
        private let lock = NSLock()
        private let context: JSContext
        private let renderSVG: JSValue

        private static let shims = """
        var window = globalThis;
        var setTimeout = function (callback) { callback.apply(null, Array.prototype.slice.call(arguments, 2)); return 0; };
        var clearTimeout = function () {};
        """

        init?() {
            guard let url = Bundle.module.url(forResource: "beautiful-mermaid.min", withExtension: "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8),
                  let context = JSContext() else { return nil }
            let atob: @convention(block) (String) -> String = { encoded in
                let cleaned = encoded.filter { !$0.isWhitespace }
                let padded = cleaned + String(repeating: "=", count: (4 - cleaned.count % 4) % 4)
                guard let data = Data(base64Encoded: padded) else { return "" }
                return String(data.map { Character(UnicodeScalar($0)) })
            }
            context.setObject(atob, forKeyedSubscript: "atob" as NSString)
            context.exceptionHandler = { context, exception in context?.exception = exception }
            context.evaluateScript(Self.shims)
            context.evaluateScript(source)
            guard let library = context.objectForKeyedSubscript("beautifulMermaid"),
                  let renderSVG = library.objectForKeyedSubscript("renderMermaidSVG"), !renderSVG.isUndefined else { return nil }
            self.context = context
            self.renderSVG = renderSVG
        }

        /// The SVG, or nil when the library throws (unsupported diagram, syntax it cannot parse).
        func render(_ text: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            context.exception = nil
            let options: [String: Any] = [
                "bg": "var(--diagram-bg)", "fg": "var(--diagram-fg)",
                "accent": "var(--diagram-accent)", "muted": "var(--diagram-muted)",
                "font": "system-ui", "transparent": true,
            ]
            guard let result = renderSVG.call(withArguments: [text, options]), context.exception == nil, result.isString else { return nil }
            return result.toString()
        }
    }

    /// beautiful-mermaid's answer per source (misses too), so re-rendering while typing does not
    /// redraw every diagram in the document.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: String?] = [:]
        private var order: [String] = []
        private let capacity = 64

        func value(for key: String) -> String?? {
            lock.lock()
            defer { lock.unlock() }
            return entries[key]
        }

        func set(_ value: String?, for key: String) {
            lock.lock()
            defer { lock.unlock() }
            if entries.updateValue(value, forKey: key) == nil {
                order.append(key)
                if order.count > capacity {
                    entries.removeValue(forKey: order.removeFirst())
                }
            }
        }
    }

    private static let engine = Engine()
    private static let cache = Cache()

    private static let fence = try! NSRegularExpression(pattern: #"<pre(?:\s+(data-sourcepos="[^"]*"))?[^>]*><code class="language-mermaid">([\s\S]*?)</code></pre>"#)
    private static let fontImport = try! NSRegularExpression(pattern: #"\s*@import url\('https://fonts\.googleapis\.com[^)]*\);"#)
    private static let fontRule = try! NSRegularExpression(pattern: #"text \{ font-family: [^}]*\}"#)

    /// Replaces every mermaid fence: beautiful-mermaid's SVG when it can draw the diagram, otherwise
    /// the pre-rendered light and dark SVGs found in `diagrams` under the fence's `key`, otherwise
    /// the code block stays.
    public static func render(_ html: String, diagrams: [String: PreRenderedDiagram] = [:]) -> String {
        guard html.contains("language-mermaid") else { return html }
        let text = html as NSString
        var result = ""
        var position = 0
        for match in fence.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            result += text.substring(with: NSRange(location: position, length: match.range.location - position))
            let source = key(for: HTMLEscaping.unescape(text.substring(with: match.range(at: 2))))
            let sourcepos = match.range(at: 1).location == NSNotFound ? "" : " " + text.substring(with: match.range(at: 1))
            if let svg = nativeSVG(for: source) {
                result += "<figure class=\"mermaid\"\(sourcepos)>" + svg + "</figure>"
            } else if let diagram = diagrams[source] {
                result += "<figure class=\"mermaid\"\(sourcepos)><div class=\"light\">" + diagram.light + "</div><div class=\"dark\">" + diagram.dark + "</div></figure>"
            } else {
                result += text.substring(with: match.range)
            }
            position = NSMaxRange(match.range)
        }
        result += text.substring(from: position)
        return result
    }

    /// The fence text as every lookup sees it: outer whitespace and newlines dropped.
    public static func key(for source: String) -> String {
        source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// beautiful-mermaid's inline SVG for a diagram, with the library's web-font import replaced by
    /// the page's font; nil for the types and syntax it does not know. Cached per source.
    public static func nativeSVG(for source: String) -> String? {
        let source = key(for: source)
        if let cached = cache.value(for: source) { return cached }
        let svg = engine?.render(normalized(source)).map { rendered in
            let withoutImport = fontImport.stringByReplacingMatches(in: rendered, range: NSRange(location: 0, length: (rendered as NSString).length), withTemplate: "")
            return fontRule.stringByReplacingMatches(in: withoutImport, range: NSRange(location: 0, length: (withoutImport as NSString).length), withTemplate: "text { font-family: var(--font-body); }")
        }
        cache.set(svg, for: source)
        return svg
    }

    /// The mermaid fences of a document that beautiful-mermaid cannot draw, in order, each once: what
    /// the caller should render with mermaid.js and pass to `render(_:diagrams:)`.
    public static func unsupportedFences(in markdown: String) -> [String] {
        guard markdown.contains("mermaid") else { return [] }
        let body = FrontMatter.split(markdown).body
        return GFMRenderer.withDocument(body) { document, _ in
            var sources: [String] = []
            var seen: Set<String> = []
            guard let iterator = cmark_iter_new(document) else { return sources }
            defer { cmark_iter_free(iterator) }
            while true {
                let event = cmark_iter_next(iterator)
                guard event != CMARK_EVENT_DONE else { break }
                guard event == CMARK_EVENT_ENTER, let node = cmark_iter_get_node(iterator),
                      cmark_node_get_type(node) == CMARK_NODE_CODE_BLOCK else { continue }
                let info = cmark_node_get_fence_info(node).map { String(cString: $0) } ?? ""
                guard info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first == "mermaid" else { continue }
                let source = key(for: cmark_node_get_literal(node).map { String(cString: $0) } ?? "")
                guard !source.isEmpty, !seen.contains(source), nativeSVG(for: source) == nil else { continue }
                seen.insert(source)
                sources.append(source)
            }
            return sources
        } ?? []
    }

    /// `graph TD; A-->B;` on one line is Mermaid the library rejects: when the header line carries a
    /// semicolon, statements go on lines of their own (semicolons inside quotes are text).
    static func normalized(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let header = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first, header.contains(";") else { return trimmed }
        var lines: [String] = []
        var current = ""
        var quoted = false
        for character in trimmed {
            switch character {
            case "\"":
                quoted.toggle()
                current.append(character)
            case ";" where !quoted, "\n" where !quoted:
                lines.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        lines.append(current)
        return lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
