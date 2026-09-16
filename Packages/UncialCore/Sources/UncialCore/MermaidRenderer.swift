import Foundation
import JavaScriptCore

/// Mermaid fences → inline SVG through beautiful-mermaid (bundled, MIT; elkjs inside, EPL-2.0) in a
/// JavaScriptCore context, so the page needs no script and Quick Look renders it too. Flowcharts,
/// state, sequence, class and ER diagrams and XY charts render; a fence the library rejects (pie,
/// gantt, a syntax error) stays a code block. Colors are CSS variables the figure maps to the
/// theme's, so the diagrams follow light and dark like the rest of the page.
enum MermaidRenderer {
    /// One renderer per process, created on the first fence. The bundle expects a browser: elkjs
    /// wants `window`, timers (never waited for: the library flushes them itself) and `atob`.
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

    private static let engine = Engine()

    private static let fence = try! NSRegularExpression(pattern: #"<pre(?:\s+(data-sourcepos="[^"]*"))?[^>]*><code class="language-mermaid">([\s\S]*?)</code></pre>"#)
    private static let fontImport = try! NSRegularExpression(pattern: #"\s*@import url\('https://fonts\.googleapis\.com[^)]*\);"#)
    private static let fontRule = try! NSRegularExpression(pattern: #"text \{ font-family: [^}]*\}"#)

    static func render(_ html: String) -> String {
        guard html.contains("language-mermaid") else { return html }
        let text = html as NSString
        var result = ""
        var position = 0
        for match in fence.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            result += text.substring(with: NSRange(location: position, length: match.range.location - position))
            let source = HTMLEscaping.unescape(text.substring(with: match.range(at: 2)))
            if let svg = self.svg(for: source) {
                let sourcepos = match.range(at: 1).location == NSNotFound ? "" : " " + text.substring(with: match.range(at: 1))
                result += "<figure class=\"mermaid\"\(sourcepos)>" + svg + "</figure>"
            } else {
                result += text.substring(with: match.range)
            }
            position = NSMaxRange(match.range)
        }
        result += text.substring(from: position)
        return result
    }

    /// Inline SVG for a diagram, with the library's web-font import replaced by the page's font.
    static func svg(for source: String) -> String? {
        guard let rendered = engine?.render(normalized(source)) else { return nil }
        let withoutImport = fontImport.stringByReplacingMatches(in: rendered, range: NSRange(location: 0, length: (rendered as NSString).length), withTemplate: "")
        return fontRule.stringByReplacingMatches(in: withoutImport, range: NSRange(location: 0, length: (withoutImport as NSString).length), withTemplate: "text { font-family: var(--font-body); }")
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
