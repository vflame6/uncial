import SwiftUI
import UncialCore
import WebKit

/// Shows the rendered document. Page JavaScript is off (Markdown is untrusted input); only
/// app-authored scripts run: scroll position save/restore, the article body swap, the scroll
/// observer user script and scroll-to-line (see `PreviewScripts`).
struct WebView: NSViewRepresentable {
    let body: String
    let title: String
    let theme: Theme
    let baseURL: URL?
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
        context.coordinator.onScroll = onScroll
        context.coordinator.show(body: body, title: title, theme: theme, baseURL: baseURL)
        context.coordinator.apply(scrollTarget)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.show(body: body, title: title, theme: theme, baseURL: baseURL)
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
        }

        weak var webView: WKWebView?
        var onScroll: ((Double) -> Void)?
        private var page: Page?
        private var currentBody: String?
        private var isLoading = false
        private var pendingBody: String?
        private var pendingScrollY: Double?
        private var appliedToken = 0
        private var lastScrollTarget: ScrollTarget?

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
            onScroll?(line)
        }

        private func reapplyScrollTarget(in webView: WKWebView) {
            guard let lastScrollTarget else { return }
            webView.evaluateJavaScript(PreviewScripts.scrollToLine(lastScrollTarget.line), completionHandler: nil)
        }

        func show(body: String, title: String, theme: Theme, baseURL: URL?) {
            guard let webView else { return }
            let newPage = Page(title: title, theme: theme, baseURL: baseURL)
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

        private func loadPage(in webView: WKWebView) {
            guard let page else { return }
            let html = HTMLDocument.wrap(body: currentBody ?? "", title: page.title, theme: page.theme)
            webView.loadHTMLString(html, baseURL: page.baseURL)
        }

        private func replaceBody(_ body: String, in webView: WKWebView) {
            let script = "document.querySelector('article.markdown-body').innerHTML = \(JavaScriptLiteral.string(body));"
            webView.evaluateJavaScript(script) { [weak self] _, _ in
                self?.reapplyScrollTarget(in: webView)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            if let scrollY = pendingScrollY {
                pendingScrollY = nil
                webView.evaluateJavaScript("window.scrollTo(0, \(scrollY));", completionHandler: nil)
            }
            if let pendingBody {
                self.pendingBody = nil
                replaceBody(pendingBody, in: webView)
            } else if pendingScrollY == nil {
                reapplyScrollTarget(in: webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.fragment != nil, Self.withoutFragment(url) == webView.url.map(Self.withoutFragment) {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            LinkOpener.open(url)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                LinkOpener.open(url)
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
