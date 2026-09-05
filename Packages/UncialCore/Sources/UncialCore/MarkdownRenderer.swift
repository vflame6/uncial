import Foundation

public struct MarkdownRenderer: Sendable {
    public init() {}

    /// GitHub-flavored Markdown → HTML fragment. Front matter is shown as a block ahead of the body.
    public func renderBody(_ markdown: String) -> String {
        let (frontMatter, body) = FrontMatter.split(markdown)
        var html = HTMLFixups.repairFootnoteBackrefs(in: GFMRenderer.render(body))
        html = HeadingAnchors.addIDs(to: html)
        if let frontMatter {
            html = FrontMatter.renderBlock(frontMatter) + html
        }
        return html
    }

    /// Standalone HTML page: CSS inlined, relative images under `baseURL` inlined as data URIs.
    public func renderDocument(_ markdown: String, title: String, baseURL: URL? = nil) -> String {
        var body = renderBody(markdown)
        if let baseURL {
            body = ImageInliner(baseURL: baseURL).inline(body)
        }
        return HTMLDocument.wrap(body: body, title: title)
    }
}
