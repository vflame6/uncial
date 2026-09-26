import SwiftUI
import UncialCore
import WebKit

/// Shows the rendered document. Page JavaScript is off (Markdown is untrusted input); only
/// app-authored scripts run: scroll position save/restore, the article body swap, the scroll
/// observer user script and scroll-to-line (see `PreviewScripts`). Navigation is the app's own or a
/// click, and with remote content off a content rule list keeps every load off the web.
struct WebView: NSViewRepresentable {
    let body: String
    let title: String
    let theme: Theme
    /// Page zoom, 1 at the system text size.
    let textScale: Double
    /// Shows the source-line gutter (`data-line` labels from the renderer).
    let lineNumbers: Bool
    let baseURL: URL?
    /// Whether the page may load from the web; off, `RemoteContentBlocker`'s rule list is installed first.
    let remoteContent: Bool
    /// Where a link to a local file that is not where the document says is looked for.
    let attachments: AttachmentSearch
    /// Receives the web view so the find bar and menu commands can address it.
    let handle: PreviewHandle
    /// 1-based fractional document line to scroll to; a new token performs the scroll.
    var scrollTarget: ScrollTarget?
    /// Called with the 1-based fractional line at the top of the viewport when the page scrolls.
    var onScroll: ((Double) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.userContentController.addUserScript(
            WKUserScript(source: PreviewScripts.observer, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        configuration.userContentController.add(ScriptMessageProxy(target: context.coordinator), name: PreviewScripts.messageHandlerName)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = .windowBackgroundColor
        #if DEBUG
        webView.isInspectable = true
        #endif
        context.coordinator.webView = webView
        handle.webView = webView
        context.coordinator.onScroll = onScroll
        context.coordinator.setLineNumbers(lineNumbers)
        context.coordinator.setTextScale(textScale)
        context.coordinator.attachments = attachments
        context.coordinator.show(body: body, title: title, theme: theme, baseURL: baseURL, remoteContent: remoteContent)
        context.coordinator.apply(scrollTarget)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.setLineNumbers(lineNumbers)
        context.coordinator.setTextScale(textScale)
        context.coordinator.attachments = attachments
        context.coordinator.show(body: body, title: title, theme: theme, baseURL: baseURL, remoteContent: remoteContent)
        context.coordinator.apply(scrollTarget)
    }

    /// Weak forwarder: the user content controller retains its handlers, the coordinator must not be retained.
    final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
        weak var target: Coordinator?

        init(target: Coordinator) {
            self.target = target
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.receive(message.body)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private struct Page: Equatable {
            let title: String
            let theme: Theme
            let baseURL: URL?
            let remoteContent: Bool
        }

        weak var webView: WKWebView?
        var onScroll: ((Double) -> Void)?
        /// Where a clicked link to a missing local file is looked for, from the page's base URL.
        var attachments: AttachmentSearch = .direct
        private var page: Page?
        private var currentBody: String?
        private var isLoading = false
        private var pendingBody: String?
        private var pendingScrollY: Double?
        /// The source line at the top of the viewport, as the page last reported it.
        private var visibleLine: Double?
        /// Where to scroll once a page that replaces a dead one has loaded.
        private var pendingLine: Double?
        private var appliedToken = 0
        private var lastScrollTarget: ScrollTarget?
        private var lineNumbers = false
        private var textScale = 1.0
        /// The rule list installed on the web view while remote content is off.
        private var blocker: WKContentRuleList?

        /// Page zoom for the text size; a load resets it, so `didFinish` applies it again.
        func setTextScale(_ scale: Double) {
            textScale = scale
            if !isLoading, let webView, webView.pageZoom != scale {
                webView.pageZoom = scale
            }
        }

        /// Turns the source-line gutter on or off in place; body swaps keep the class.
        func setLineNumbers(_ flag: Bool) {
            guard flag != lineNumbers else { return }
            lineNumbers = flag
            if !isLoading, let webView {
                applyLineNumbers(in: webView)
            }
        }

        private func applyLineNumbers(in webView: WKWebView) {
            webView.evaluateJavaScript("document.documentElement.classList.toggle('line-numbers', \(lineNumbers));", completionHandler: nil)
        }

        /// Performs a new scroll request now, or once the page has loaded; nil forgets the last one.
        func apply(_ target: ScrollTarget?) {
            guard let target else {
                lastScrollTarget = nil
                return
            }
            guard target.token != appliedToken else { return }
            appliedToken = target.token
            lastScrollTarget = target
            if !isLoading, let webView {
                webView.evaluateJavaScript(PreviewScripts.scrollToLine(target.line), completionHandler: nil)
            }
        }

        func receive(_ body: Any) {
            guard let dictionary = body as? [String: Any], let line = dictionary["line"] as? Double else { return }
            visibleLine = line
            onScroll?(line)
        }

        private func reapplyScrollTarget(in webView: WKWebView) {
            guard let lastScrollTarget else { return }
            webView.evaluateJavaScript(PreviewScripts.scrollToLine(lastScrollTarget.line), completionHandler: nil)
        }

        func show(body: String, title: String, theme: Theme, baseURL: URL?, remoteContent: Bool) {
            guard let webView else { return }
            let newPage = Page(title: title, theme: theme, baseURL: baseURL, remoteContent: remoteContent)
            if page != newPage {
                let isFirstLoad = page == nil
                page = newPage
                currentBody = body
                pendingBody = nil
                isLoading = true
                if isFirstLoad {
                    loadPage(in: webView)
                } else {
                    webView.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
                        guard let self else { return }
                        self.pendingScrollY = value as? Double
                        self.loadPage(in: webView)
                    }
                }
                return
            }
            guard body != currentBody else { return }
            currentBody = body
            if isLoading {
                pendingBody = body
            } else {
                replaceBody(body, in: webView)
            }
        }

        /// Loads the page once the web view's rule list matches `page.remoteContent`: the blocker is
        /// added before a page that must stay off the web and removed before one that may load from it.
        private func loadPage(in webView: WKWebView) {
            guard let page else { return }
            let html = HTMLDocument.wrap(body: currentBody ?? "", title: page.title, theme: page.theme, lineNumbers: lineNumbers)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let controller = webView.configuration.userContentController
                if page.remoteContent {
                    if let blocker {
                        controller.remove(blocker)
                        self.blocker = nil
                    }
                } else if blocker == nil, let list = await RemoteContentBlocker.shared.ruleList() {
                    controller.add(list)
                    blocker = list
                }
                // A newer page may have been requested while the list was compiling.
                guard self.page == page else { return }
                webView.loadHTMLString(html, baseURL: page.baseURL)
            }
        }

        /// Swaps the page's whole body, the article included, so the document's own HTML parses as it did
        /// in the first load: a raw `</article>` there closes the article early, and replacing the article's
        /// content alone left a second copy of everything after it (BUG-30).
        private func replaceBody(_ body: String, in webView: WKWebView) {
            let article = "<article class=\"markdown-body\">\n\(body)\n</article>"
            let script = "document.body.innerHTML = \(JavaScriptLiteral.string(article));"
            webView.evaluateJavaScript(script) { [weak self] _, _ in
                self?.reapplyScrollTarget(in: webView)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            applyLineNumbers(in: webView)
            if webView.pageZoom != textScale {
                webView.pageZoom = textScale
            }
            if let scrollY = pendingScrollY {
                pendingScrollY = nil
                webView.evaluateJavaScript("window.scrollTo(0, \(scrollY));", completionHandler: nil)
            } else if let line = pendingLine {
                pendingLine = nil
                webView.evaluateJavaScript(PreviewScripts.scrollToLine(line), completionHandler: nil)
            }
            if let pendingBody {
                self.pendingBody = nil
                replaceBody(pendingBody, in: webView)
            } else {
                reapplyScrollTarget(in: webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        /// WebKit lost the page's process (a crash, memory pressure, Activity Monitor): the document is
        /// gone, and body swaps would run against nothing. The page is loaded again with the latest body
        /// and scrolled back to the line it showed; its scroll offset went with the process (STAB-7,
        /// 2026-09-26: the preview stayed blank until the theme or the mode changed).
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard page != nil else { return }
            pendingBody = nil
            pendingScrollY = nil
            pendingLine = visibleLine
            isLoading = true
            loadPage(in: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated {
                if url.fragment != nil, Self.withoutFragment(url) == webView.url.map(Self.withoutFragment) {
                    decisionHandler(.allow)
                } else {
                    decisionHandler(.cancel)
                    LinkOpener.open(url, from: page?.baseURL, attachments: attachments, in: webView.window)
                }
                return
            }
            // Only the app's own loads pass (loadHTMLString: about:blank, or the document's directory
            // as the base): a document cannot send the view elsewhere, a meta refresh for one, and
            // nothing opens on its behalf.
            decisionHandler(["about", "file"].contains(url.scheme?.lowercased() ?? "") ? .allow : .cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                LinkOpener.open(url, from: page?.baseURL, attachments: attachments, in: webView.window)
            }
            return nil
        }

        nonisolated private static func withoutFragment(_ url: URL) -> String {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            components?.fragment = nil
            return components?.string ?? url.absoluteString
        }
    }
}
