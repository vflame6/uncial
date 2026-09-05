/// GitHub-like styling. Light palette on `:root`, dark palette under `prefers-color-scheme: dark`.
public enum Stylesheet {
    public static let css = #"""
    :root {
      color-scheme: light dark;
      --bg: #ffffff;
      --fg: #1f2328;
      --muted: #59636e;
      --border: #d1d9e0;
      --border-muted: #d8dee4;
      --accent: #0969da;
      --code-bg: #f6f8fa;
      --row-alt: #f6f8fa;
      --mark: #fff8c5;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0d1117;
        --fg: #f0f6fc;
        --muted: #9198a1;
        --border: #3d444d;
        --border-muted: #30363d;
        --accent: #4493f8;
        --code-bg: #151b23;
        --row-alt: #151b23;
        --mark: #3a2d00;
      }
    }
    html, body { margin: 0; padding: 0; background: var(--bg); color: var(--fg); }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif, "Apple Color Emoji";
      font-size: 16px;
      line-height: 1.5;
      -webkit-text-size-adjust: 100%;
      word-wrap: break-word;
    }
    .markdown-body { max-width: 860px; margin: 0 auto; padding: 32px 40px 64px; box-sizing: border-box; }
    @media (max-width: 640px) { .markdown-body { padding: 16px; } }
    .markdown-body > :first-child { margin-top: 0; }
    .markdown-body > :last-child { margin-bottom: 0; }
    h1, h2, h3, h4, h5, h6 { margin-top: 24px; margin-bottom: 16px; font-weight: 600; line-height: 1.25; }
    h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--border-muted); }
    h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--border-muted); }
    h3 { font-size: 1.25em; }
    h4 { font-size: 1em; }
    h5 { font-size: .875em; }
    h6 { font-size: .85em; color: var(--muted); }
    p, blockquote, ul, ol, dl, table, pre, details { margin-top: 0; margin-bottom: 16px; }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    img { max-width: 100%; box-sizing: content-box; }
    code, pre, kbd, samp { font-family: ui-monospace, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace; }
    code { padding: .2em .4em; margin: 0; font-size: 85%; background: var(--code-bg); border-radius: 6px; white-space: break-spaces; }
    pre { padding: 16px; overflow: auto; font-size: 85%; line-height: 1.45; background: var(--code-bg); border-radius: 6px; }
    pre code { padding: 0; margin: 0; font-size: 100%; background: transparent; border: 0; white-space: pre; word-break: normal; }
    blockquote { margin: 0 0 16px; padding: 0 1em; color: var(--muted); border-left: .25em solid var(--border); }
    blockquote > :first-child { margin-top: 0; }
    blockquote > :last-child { margin-bottom: 0; }
    ul, ol { padding-left: 2em; }
    ul ul, ul ol, ol ol, ol ul { margin-top: 0; margin-bottom: 0; }
    li + li { margin-top: .25em; }
    li > p { margin-top: 16px; }
    li:has(> input[type=checkbox]) { list-style: none; margin-left: -1.5em; }
    li > input[type=checkbox] { margin: 0 .4em .25em 0; vertical-align: middle; }
    table { border-spacing: 0; border-collapse: collapse; display: block; width: max-content; max-width: 100%; overflow: auto; }
    th, td { padding: 6px 13px; border: 1px solid var(--border); }
    th { font-weight: 600; }
    tr { background: var(--bg); border-top: 1px solid var(--border-muted); }
    tbody tr:nth-child(2n) { background: var(--row-alt); }
    hr { height: .25em; padding: 0; margin: 24px 0; background: var(--border); border: 0; }
    details summary { cursor: pointer; font-weight: 600; }
    mark { background: var(--mark); color: inherit; }
    kbd {
      display: inline-block; padding: 3px 5px; font-size: 11px; line-height: 10px; vertical-align: middle;
      background: var(--code-bg); border: 1px solid var(--border); border-radius: 6px; box-shadow: inset 0 -1px 0 var(--border);
    }
    sup.footnote-ref { font-size: 75%; }
    a.footnote-backref { font-family: Menlo, "DejaVu Sans Mono", monospace; text-decoration: none; }
    section.footnotes { margin-top: 32px; padding-top: 8px; font-size: 85%; color: var(--muted); border-top: 1px solid var(--border); }
    section.footnotes p { margin-bottom: 8px; }
    pre.front-matter { color: var(--muted); font-size: 80%; background: transparent; border: 1px dashed var(--border); }
    :target { scroll-margin-top: 16px; }
    """#
}
