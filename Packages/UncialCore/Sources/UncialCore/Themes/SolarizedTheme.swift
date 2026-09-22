extension Stylesheet {
    /// Ethan Schoonover's Solarized: light on base3, dark on base03.
    static let solarized = #"""
    :root {
      color-scheme: light dark;
      --bg: #fdf6e3; --fg: #657b83; --heading: #586e75; --muted: #93a1a1;
      --border: #eee8d5; --border-muted: #eee8d5; --accent: #268bd2;
      --code-bg: #eee8d5; --code-fg: #586e75; --row-alt: #f6efdc;
      --mark: rgba(181, 137, 0, .25); --quote-border: #93a1a1;
      --font-body: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif, "Apple Color Emoji";
      --font-mono: ui-monospace, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
      --font-size: 16px; --line-height: 1.6; --content-width: 820px; --radius: 4px;
      --heading-weight: 600;
      --h1-size: 2em; --h2-size: 1.5em; --h3-size: 1.25em; --h4-size: 1em; --h5-size: .875em; --h6-size: .85em;
      --h1-border: 1px solid var(--border); --h2-border: 1px solid var(--border);
      --code-comment: #93a1a1; --code-keyword: #859900; --code-string: #2aa198; --code-number: #d33682; --code-type: #b58900; --code-function: #268bd2;
      --code-variable: #6c71c4; --code-meta: #cb4b16; --code-tag: #268bd2; --code-addition: #859900; --code-deletion: #dc322f;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #002b36; --fg: #839496; --heading: #93a1a1; --muted: #586e75;
        --border: #073642; --border-muted: #073642; --accent: #268bd2;
        --code-bg: #073642; --code-fg: #93a1a1; --row-alt: #03303c;
        --mark: rgba(181, 137, 0, .35); --quote-border: #586e75;
        --code-comment: #586e75;
      }
    }
    a:hover { color: #2aa198; }
    strong { color: var(--heading); }
    """#
}
