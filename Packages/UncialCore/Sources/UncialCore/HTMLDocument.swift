public enum HTMLDocument {
    /// The Content-Security-Policy of a page that must not reach the web (Quick Look, which has no
    /// content rule list, with remote content off): inline styles and `data:`/`file:` media only, no
    /// script, fonts only from `data:`, no base URL, no form target.
    public static let offlinePolicy = "default-src 'none'; img-src data: file:; media-src data: file:; style-src 'unsafe-inline'; font-src data:; base-uri 'none'; form-action 'none'"

    /// A complete page: the theme's CSS inlined, the rendered fragment inside `article.markdown-body`.
    /// `lineNumbers` turns on the source-line gutter (needs `data-line` labels from `SourcePositions.annotate`).
    /// `contentSecurityPolicy` goes first in the head, ahead of anything it governs.
    public static func wrap(body: String, title: String, theme: Theme = .default, lineNumbers: Bool = false, contentSecurityPolicy: String? = nil) -> String {
        """
        <!DOCTYPE html>
        <html data-theme="\(theme.rawValue)"\(lineNumbers ? " class=\"line-numbers\"" : "")>
        <head>
        \(contentSecurityPolicy.map { "<meta http-equiv=\"Content-Security-Policy\" content=\"\($0)\">\n" } ?? "")<meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(HTMLEscaping.escape(title))</title>
        <style>
        \(Stylesheet.css(for: theme))
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }
}
