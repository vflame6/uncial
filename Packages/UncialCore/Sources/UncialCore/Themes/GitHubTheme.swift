extension Stylesheet {
    /// GitHub Primer palette, light and dark.
    static let github = #"""
    :root {
      color-scheme: light dark;
      --bg: #ffffff; --fg: #1f2328; --heading: #1f2328; --muted: #59636e;
      --border: #d1d9e0; --border-muted: #d8dee4; --accent: #0969da;
      --code-bg: #f6f8fa; --code-fg: currentColor; --row-alt: #f6f8fa; --mark: #fff8c5; --quote-border: #d1d9e0;
      --font-body: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif, "Apple Color Emoji";
      --font-mono: ui-monospace, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
      --font-size: 16px; --line-height: 1.5; --content-width: 860px; --radius: 6px;
      --heading-weight: 600;
      --h1-size: 2em; --h2-size: 1.5em; --h3-size: 1.25em; --h4-size: 1em; --h5-size: .875em; --h6-size: .85em;
      --h1-border: 1px solid var(--border-muted); --h2-border: 1px solid var(--border-muted);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0d1117; --fg: #f0f6fc; --heading: #f0f6fc; --muted: #9198a1;
        --border: #3d444d; --border-muted: #30363d; --accent: #4493f8;
        --code-bg: #151b23; --row-alt: #151b23; --mark: #3a2d00; --quote-border: #3d444d;
      }
    }
    """#
}
