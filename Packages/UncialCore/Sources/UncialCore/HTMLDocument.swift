public enum HTMLDocument {
    /// A complete page: the theme's CSS inlined, the rendered fragment inside `article.markdown-body`.
    /// `lineNumbers` turns on the source-line gutter (needs `data-line` labels from `SourcePositions.annotate`).
    public static func wrap(body: String, title: String, theme: Theme = .default, lineNumbers: Bool = false) -> String {
        """
        <!DOCTYPE html>
        <html data-theme="\(theme.rawValue)"\(lineNumbers ? " class=\"line-numbers\"" : "")>
        <head>
        <meta charset="utf-8">
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
