/// Shared layout and element rules. Every color, font and size comes from a custom property
/// that each theme sets (light values on `:root`, dark ones under `prefers-color-scheme: dark`).
/// The `.hljs-…` rules color highlighted code through the `--code-…` variables, one per
/// `CodeHighlighter.Scope`, which every theme sets to its `SyntaxPalette` values; the `.callout` rules
/// take their colors from `--callout-<role>` variables, one per `Callouts.Role`, set to `CalloutPalette`.
public enum Stylesheet {
    /// The base sheet followed by the theme's variables and overrides.
    public static func css(for theme: Theme) -> String {
        base + "\n" + themeBlock(for: theme)
    }

    static func themeBlock(for theme: Theme) -> String {
        switch theme {
        case .macOS: macOS
        case .github: github
        case .solarized: solarized
        }
    }

    static let base = #"""
    html, body { margin: 0; padding: 0; background: var(--bg); color: var(--fg); }
    body {
      font-family: var(--font-body);
      font-size: var(--font-size);
      line-height: var(--line-height);
      -webkit-text-size-adjust: 100%;
      word-wrap: break-word;
    }
    .markdown-body { max-width: var(--content-width); margin: 0 auto; padding: 32px 40px 64px; box-sizing: border-box; }
    @media (max-width: 640px) { .markdown-body { padding: 16px; } }
    .markdown-body > :first-child { margin-top: 0; }
    .markdown-body > :last-child { margin-bottom: 0; }
    html.line-numbers .markdown-body { position: relative; padding-left: 4.5em; }
    html.line-numbers .markdown-body [data-line]::before { content: attr(data-line); position: absolute; left: 0; width: 3.5em; text-align: right; font-family: var(--font-mono); font-size: calc(var(--font-size) * .85); line-height: calc(var(--line-height) / .85); color: var(--muted); user-select: none; pointer-events: none; }
    html.line-numbers .markdown-body .line::before { font-size: inherit; line-height: inherit; }
    h1, h2, h3, h4, h5, h6 { margin-top: 24px; margin-bottom: 16px; font-weight: var(--heading-weight); line-height: 1.25; color: var(--heading); }
    h1 { font-size: var(--h1-size); padding-bottom: .3em; border-bottom: var(--h1-border); }
    h2 { font-size: var(--h2-size); padding-bottom: .3em; border-bottom: var(--h2-border); }
    h3 { font-size: var(--h3-size); }
    h4 { font-size: var(--h4-size); }
    h5 { font-size: var(--h5-size); }
    h6 { font-size: var(--h6-size); color: var(--muted); }
    p, blockquote, ul, ol, dl, table, pre, details { margin-top: 0; margin-bottom: 16px; }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    img { max-width: 100%; box-sizing: content-box; }
    code, pre, kbd, samp { font-family: var(--font-mono); }
    code { padding: .2em .4em; margin: 0; font-size: 85%; color: var(--code-fg); background: var(--code-bg); border-radius: var(--radius); white-space: break-spaces; }
    pre { padding: 16px; overflow: auto; font-size: 85%; line-height: 1.45; color: var(--code-fg); background: var(--code-bg); border-radius: var(--radius); }
    pre code { padding: 0; margin: 0; font-size: 100%; color: inherit; background: transparent; border: 0; white-space: pre; word-break: normal; }
    .hljs-comment, .hljs-quote { color: var(--code-comment); }
    .hljs-keyword, .hljs-doctag, .hljs-template-tag { color: var(--code-keyword); }
    .hljs-string, .hljs-regexp, .hljs-char.escape_, .hljs-code, .hljs-formula { color: var(--code-string); }
    .hljs-number, .hljs-literal, .hljs-symbol, .hljs-bullet { color: var(--code-number); }
    .hljs-type, .hljs-built_in, .hljs-title.class_ { color: var(--code-type); }
    .hljs-title, .hljs-section { color: var(--code-function); }
    .hljs-variable, .hljs-template-variable, .hljs-attr, .hljs-attribute, .hljs-property, .hljs-selector-attr, .hljs-selector-pseudo { color: var(--code-variable); }
    .hljs-meta { color: var(--code-meta); }
    .hljs-name, .hljs-selector-tag, .hljs-selector-id, .hljs-selector-class { color: var(--code-tag); }
    .hljs-subst { color: var(--fg); }
    .hljs-addition { color: var(--code-addition); background: color-mix(in srgb, var(--code-addition) 12%, transparent); }
    .hljs-deletion { color: var(--code-deletion); background: color-mix(in srgb, var(--code-deletion) 12%, transparent); }
    .hljs-emphasis { font-style: italic; }
    .hljs-strong { font-weight: 600; }
    blockquote { margin: 0 0 16px; padding: 0 1em; color: var(--muted); border-left: .25em solid var(--quote-border); }
    blockquote > :first-child { margin-top: 0; }
    blockquote > :last-child { margin-bottom: 0; }
    .callout { --callout-color: var(--callout-note); margin: 0 0 16px; padding: 12px 16px; border-radius: var(--radius); background: color-mix(in srgb, var(--callout-color) 10%, transparent); }
    .callout[data-callout="abstract"], .callout[data-callout="tip"] { --callout-color: var(--callout-tip); }
    .callout[data-callout="success"] { --callout-color: var(--callout-success); }
    .callout[data-callout="question"] { --callout-color: var(--callout-question); }
    .callout[data-callout="warning"] { --callout-color: var(--callout-warning); }
    .callout[data-callout="failure"], .callout[data-callout="danger"], .callout[data-callout="bug"] { --callout-color: var(--callout-danger); }
    .callout[data-callout="example"] { --callout-color: var(--callout-example); }
    .callout[data-callout="quote"] { --callout-color: var(--callout-quote); }
    .callout-title { display: flex; align-items: center; gap: 8px; margin: 0; color: var(--callout-color); font-weight: 600; }
    .callout-icon, .callout-fold { display: inline-flex; flex: none; }
    .callout-icon svg, .callout-fold svg { width: 18px; height: 18px; }
    .callout-fold { opacity: .7; transition: transform .15s; }
    details[open] > .callout-title .callout-fold { transform: rotate(90deg); }
    summary.callout-title { cursor: pointer; list-style: none; }
    summary.callout-title::-webkit-details-marker { display: none; }
    .callout-content { margin-top: 8px; }
    .callout-content > :last-child { margin-bottom: 0; }
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
    math { font-family: "STIX Two Math", "Latin Modern Math", STIXGeneral, serif; }
    p.math { margin: 16px 0; }
    figure.mermaid { margin: 16px 0; text-align: center; --diagram-bg: var(--bg); --diagram-fg: var(--fg); --diagram-accent: var(--accent); --diagram-muted: var(--muted); }
    figure.mermaid svg { max-width: 100%; height: auto; }
    figure.mermaid .dark { display: none; }
    @media (prefers-color-scheme: dark) { figure.mermaid .light { display: none; } figure.mermaid .dark { display: block; } }
    details summary { cursor: pointer; font-weight: 600; }
    mark { background: var(--mark); color: inherit; }
    kbd {
      display: inline-block; padding: 3px 5px; font-size: 11px; line-height: 10px; vertical-align: middle;
      background: var(--code-bg); border: 1px solid var(--border); border-radius: var(--radius); box-shadow: inset 0 -1px 0 var(--border);
    }
    sup.footnote-ref { font-size: 75%; }
    a.footnote-backref { font-family: var(--font-mono); text-decoration: none; }
    section.footnotes { margin-top: 32px; padding-top: 8px; font-size: 85%; color: var(--muted); border-top: 1px solid var(--border); }
    section.footnotes p { margin-bottom: 8px; }
    pre.front-matter { color: var(--muted); font-size: 80%; background: transparent; border: 1px dashed var(--border); }
    :target { scroll-margin-top: 16px; }
    """#
}
