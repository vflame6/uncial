extension Stylesheet {
    /// Looks like a native document: WebKit's semantic system colors (which follow the effective
    /// appearance on their own), SF Pro, and the macOS text-style sizes for headings.
    static let macOS = #"""
    :root {
      color-scheme: light dark;
      --bg: -apple-system-text-background;
      --fg: -apple-system-label;
      --heading: -apple-system-label;
      --muted: -apple-system-secondary-label;
      --border: -apple-system-separator;
      --border-muted: -apple-system-grid;
      --accent: -apple-system-blue;
      --code-bg: color-mix(in srgb, -apple-system-label 6%, transparent);
      --code-fg: currentColor;
      --row-alt: -apple-system-odd-alternating-content-background;
      --mark: -apple-system-find-highlight-background;
      --quote-border: -apple-system-quaternary-label;
      --font-body: -apple-system, system-ui, "SF Pro Text", "Helvetica Neue", Helvetica, sans-serif, "Apple Color Emoji";
      --font-mono: ui-monospace, "SF Mono", Menlo, monospace;
      --font-size: 15px; --line-height: 1.5; --content-width: 760px; --radius: 6px;
      --heading-weight: 600;
      --h1-size: 26px; --h2-size: 22px; --h3-size: 17px; --h4-size: 15px; --h5-size: 13px; --h6-size: 13px;
      --h1-border: 1px solid var(--border-muted); --h2-border: 1px solid var(--border-muted);
      --code-comment: #5d6c79; --code-keyword: #9b2393; --code-string: #c41a16; --code-number: #1c00cf; --code-type: #3e8087; --code-function: #4b21b0;
      --code-variable: #0f68a0; --code-meta: #643820; --code-tag: #0b4f79; --code-addition: #1a7f37; --code-deletion: #cf222e;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --code-bg: color-mix(in srgb, -apple-system-label 10%, transparent);
        --code-comment: #6c7986; --code-keyword: #fc5fa3; --code-string: #fc6a5d; --code-number: #d0bf69; --code-type: #5dd8ff; --code-function: #a167e6;
        --code-variable: #67b7a4; --code-meta: #fd8f3f; --code-tag: #41a1c0; --code-addition: #3fb950; --code-deletion: #f85149;
      }
    }
    body { -webkit-font-smoothing: antialiased; }
    h1, h2 { font-weight: 700; }
    h1 { letter-spacing: -0.02em; }
    h2 { letter-spacing: -0.015em; margin-top: 32px; }
    h3 { letter-spacing: -0.01em; }
    pre { border: 1px solid var(--border-muted); }
    blockquote { border-left-width: 3px; }
    hr { height: 1px; }
    th { border-bottom-width: 2px; }
    """#
}
