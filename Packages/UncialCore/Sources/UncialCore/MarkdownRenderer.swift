import Foundation

public struct MarkdownRenderer: Sendable {
    public init() {}

    /// GitHub-flavored Markdown → HTML fragment. Front matter is shown as a block ahead of the body.
    /// With a `baseURL` (the document file or its directory), relative images become `data:` URIs.
    /// With `sourcePositions`, block elements carry `data-sourcepos` line ranges of the full document
    /// and `data-line` labels for the gutter (`SourcePositions.annotate`). `diagrams` holds the mermaid
    /// fences drawn ahead of time by mermaid.js (see `MermaidRenderer.unsupportedFences`), keyed by source.
    /// Fenced code in a language `CodeHighlighter` knows comes back with highlight.js spans. Unless
    /// `remoteContent` is allowed, references to the web on media and resource elements are disarmed
    /// (`RemoteContent.block`); links stay. An image that is not where the document says is looked
    /// for by `attachments`. Blockquotes that start with `[!type]` become callouts (`Callouts`).
    public func renderBody(_ markdown: String, baseURL: URL? = nil, sourcePositions: Bool = false, diagrams: [String: PreRenderedDiagram] = [:], remoteContent: Bool = false, attachments: AttachmentSearch = .direct) -> String {
        let (frontMatter, body) = FrontMatter.split(markdown)
        // Formulas skip cmark: its escapes and emphasis would rewrite their TeX.
        let math = MathSource(body)
        var html = HTMLFixups.repairFootnoteBackrefs(in: GFMRenderer.render(math.masked, sourcePositions: sourcePositions))
        html = math.restore(in: html)
        html = Callouts.render(html)
        html = HeadingAnchors.addIDs(to: html)
        html = MathRenderer.render(html)
        html = MermaidRenderer.render(html, diagrams: diagrams)
        html = CodeHighlighter.render(html)
        if sourcePositions {
            if frontMatter != nil {
                html = SourcePositions.shift(html, by: FrontMatter.bodyLineOffset(of: markdown))
            }
            html = SourcePositions.annotate(html)
        }
        if let frontMatter {
            html = FrontMatter.renderBlock(frontMatter) + html
        }
        // Before the inliner: it only writes `data:` URIs, and the sanitizer's regexes would otherwise
        // scan every image's base64 on every render (PERF-6, 0.4 s for five photos).
        if !remoteContent {
            html = RemoteContent.block(in: html)
        }
        if let baseURL {
            html = ImageInliner(baseURL: baseURL, attachments: attachments).inline(html)
        }
        return html
    }

    /// Standalone HTML page with the theme's CSS inlined (Quick Look's). With `remoteContent` off it
    /// also carries `HTMLDocument.offlinePolicy`, since nothing else guards that page.
    public func renderDocument(_ markdown: String, title: String, baseURL: URL? = nil, theme: Theme = .default, diagrams: [String: PreRenderedDiagram] = [:],
                               remoteContent: Bool = false, attachments: AttachmentSearch = .direct, appearance: PageAppearance = .system) -> String {
        HTMLDocument.wrap(body: renderBody(markdown, baseURL: baseURL, diagrams: diagrams, remoteContent: remoteContent, attachments: attachments),
                          title: title, theme: theme, contentSecurityPolicy: remoteContent ? nil : HTMLDocument.offlinePolicy, appearance: appearance)
    }
}
