import Foundation

enum HTMLFixups {
    /// swift-cmark (branch gfm, src/html.c) emits `aria-label="Back to reference 1↩</a>`
    /// for the first footnote back-reference, missing the closing `">`.
    private static let brokenBackref = try! NSRegularExpression(
        pattern: #"(aria-label="Back to reference [^"<>]*)(↩</a>)"#
    )

    static func repairFootnoteBackrefs(in html: String) -> String {
        let range = NSRange(html.startIndex..., in: html)
        return brokenBackref.stringByReplacingMatches(in: html, range: range, withTemplate: "$1\">$2")
    }
}
