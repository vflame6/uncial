import WebKit

/// Blocks every load from the web: the content rule list `WebView` adds while remote content is
/// off, so a document cannot reach a server through an image, a style sheet, media or anything else
/// a raw HTML block names, and that `DiagramWebRenderer` always adds to its hidden stage. Compiled
/// once per process (WebKit keeps the compiled list on disk under the identifier) and shared.
@MainActor
final class RemoteContentBlocker {
    static let shared = RemoteContentBlocker()
    static let identifier = "uncial-block-remote-content"
    /// Content-blocker regexes know no alternation, hence one rule per scheme.
    static let rules = """
    [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},
     {"trigger":{"url-filter":"^ftp://"},"action":{"type":"block"}},
     {"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}}]
    """

    private var ruleList: WKContentRuleList?
    private var compilation: Task<WKContentRuleList?, Never>?

    /// The compiled list, or nil when WebKit cannot compile it; then the renderer's
    /// `RemoteContent.block` pass is all that stands, which already disarms what cmark can emit.
    func ruleList() async -> WKContentRuleList? {
        if let ruleList { return ruleList }
        if let compilation { return await compilation.value }
        let task = Task { () -> WKContentRuleList? in
            await withCheckedContinuation { continuation in
                WKContentRuleListStore.default().compileContentRuleList(forIdentifier: Self.identifier, encodedContentRuleList: Self.rules) { list, _ in
                    continuation.resume(returning: list)
                }
            }
        }
        compilation = task
        let list = await task.value
        ruleList = list
        compilation = nil
        return list
    }
}
