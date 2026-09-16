import Foundation

public struct MarkdownRenderer: Sendable {
    public init() {}

    /// GitHub-flavored Markdown → HTML fragment. Front matter is shown as a block ahead of the body.
    /// With a `baseURL` (the document file or its directory), relative images become `data:` URIs.
    /// With `sourcePositions`, block elements carry `data-sourcepos` line ranges of the full document
    /// and `data-line` labels for the gutter (`SourcePositions.annotate`).
    public func renderBody(_ markdown: String, baseURL: URL? = nil, sourcePositions: Bool = false) -> String {
        let (frontMatter, body) = FrontMatter.split(markdown)
        var html = HTMLFixups.repairFootnoteBackrefs(in: GFMRenderer.render(body, sourcePositions: sourcePositions))
        html = HeadingAnchors.addIDs(to: html)
        html = MathRenderer.render(html)
        html = MermaidRenderer.render(html)
        if sourcePositions {
            if frontMatter != nil {
                html = SourcePositions.shift(html, by: FrontMatter.bodyLineOffset(of: markdown))
            }
            html = SourcePositions.annotate(html)
        }
        if let frontMatter {
            html = FrontMatter.renderBlock(frontMatter) + html
        }
        if let baseURL {
            html = ImageInliner(baseURL: baseURL).inline(html)
        }
        return html
    }

    /// Standalone HTML page with the theme's CSS inlined.
    public func renderDocument(_ markdown: String, title: String, baseURL: URL? = nil, theme: Theme = .default) -> String {
        HTMLDocument.wrap(body: renderBody(markdown, baseURL: baseURL), title: title, theme: theme)
    }
}
