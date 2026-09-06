import Foundation

public struct MarkdownRenderer: Sendable {
    public init() {}

    /// GitHub-flavored Markdown → HTML fragment. Front matter is shown as a block ahead of the body.
    /// With a `baseURL` (the document file or its directory), relative images become `data:` URIs.
    public func renderBody(_ markdown: String, baseURL: URL? = nil) -> String {
        let (frontMatter, body) = FrontMatter.split(markdown)
        var html = HTMLFixups.repairFootnoteBackrefs(in: GFMRenderer.render(body))
        html = HeadingAnchors.addIDs(to: html)
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
