import Foundation
import JavaScriptCore

/// TeX math → MathML through KaTeX (bundled, MIT) in a JavaScriptCore context, so the page needs
/// no script and Quick Look renders it too. Handles inline `$…$`, display `$$…$$` and
/// ```` ```math ```` fences; text inside other code is left alone. Bad TeX comes back as KaTeX's
/// red error span with the source, never as an exception. `mathML(_:display:)` renders one formula
/// for the app's editor, which draws it through WebKit.
public enum MathRenderer {
    /// One KaTeX instance per process. JavaScriptCore serializes calls on a context, and the lock
    /// keeps the render calls from interleaving on top of that.
    private final class Engine: @unchecked Sendable {
        private let lock = NSLock()
        private let context: JSContext
        private let katex: JSValue

        init?() {
            guard let url = Bundle.module.url(forResource: "katex.min", withExtension: "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8),
                  let context = JSContext() else { return nil }
            context.evaluateScript(source)
            guard let katex = context.objectForKeyedSubscript("katex"), !katex.isUndefined else { return nil }
            self.context = context
            self.katex = katex
        }

        func render(_ tex: String, display: Bool) -> String? {
            lock.lock()
            defer { lock.unlock() }
            let options: [String: Any] = ["displayMode": display, "output": "mathml", "throwOnError": false, "strict": "ignore"]
            guard let rendered = katex.invokeMethod("renderToString", withArguments: [tex, options]), rendered.isString else { return nil }
            return rendered.toString()
        }
    }

    private static let engine = Engine()

    private static let mathFence = try! NSRegularExpression(pattern: #"<pre(?:\s+(data-sourcepos="[^"]*"))?[^>]*><code class="language-math">([\s\S]*?)</code></pre>"#)
    private static let protected = try! NSRegularExpression(pattern: #"<pre\b[^>]*>[\s\S]*?</pre>|<code\b[^>]*>[\s\S]*?</code>"#)
    private static let display = try! NSRegularExpression(pattern: #"\$\$([\s\S]+?)\$\$"#)
    private static let inline = try! NSRegularExpression(pattern: #"(?<![\w$\\])\$(?![\s$])([^$\n]+?)(?<![\s\\])\$(?![\d$])"#)

    static func render(_ html: String) -> String {
        guard html.contains("$") || html.contains("language-math") else { return html }
        var output = replace(mathFence, in: html) { match, text in
            let sourcepos = match.range(at: 1).location == NSNotFound ? "" : " " + text.substring(with: match.range(at: 1))
            let tex = text.substring(with: match.range(at: 2)).trimmingCharacters(in: .newlines)
            return "<p class=\"math\"\(sourcepos)>" + mathML(unescaped(tex), display: true) + "</p>"
        }
        guard output.contains("$") else { return output }
        // Math only outside code: process the stretches between protected regions.
        let text = output as NSString
        var result = ""
        var position = 0
        for match in protected.matches(in: output, range: NSRange(location: 0, length: text.length)) {
            result += renderDollars(text.substring(with: NSRange(location: position, length: match.range.location - position)))
            result += text.substring(with: match.range)
            position = NSMaxRange(match.range)
        }
        result += renderDollars(text.substring(from: position))
        output = result
        return output
    }

    private static func renderDollars(_ html: String) -> String {
        guard html.contains("$") else { return html }
        let withDisplay = replace(display, in: html) { match, text in
            mathML(unescaped(text.substring(with: match.range(at: 1))), display: true)
        }
        return replace(inline, in: withDisplay) { match, text in
            mathML(unescaped(text.substring(with: match.range(at: 1))), display: false)
        }
    }

    private static func replace(_ regex: NSRegularExpression, in html: String, with replacement: (NSTextCheckingResult, NSString) -> String) -> String {
        let text = html as NSString
        var result = ""
        var position = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            result += text.substring(with: NSRange(location: position, length: match.range.location - position))
            result += replacement(match, text)
            position = NSMaxRange(match.range)
        }
        result += text.substring(from: position)
        return result
    }

    /// KaTeX's MathML for `tex`; without KaTeX (no resource) the source stays as escaped text.
    public static func mathML(_ tex: String, display: Bool) -> String {
        engine?.render(tex, display: display) ?? HTMLEscaping.escape(display ? "$$\(tex)$$" : "$\(tex)$")
    }

    /// cmark escaped the text; KaTeX wants the TeX itself.
    private static func unescaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
