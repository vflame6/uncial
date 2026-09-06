public enum HTMLDocument {
    /// A complete page: the theme's CSS inlined, the rendered fragment inside `article.markdown-body`.
    public static func wrap(body: String, title: String, theme: Theme = .default) -> String {
        """
        <!DOCTYPE html>
        <html data-theme="\(theme.rawValue)">
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
