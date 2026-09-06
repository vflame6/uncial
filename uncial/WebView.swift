import SwiftUI
import UncialCore
import WebKit

/// Shows the rendered document. Page JavaScript is off (Markdown is untrusted input); the app
/// itself runs two scripts: reading/restoring the scroll position and swapping the article body.
struct WebView: NSViewRepresentable {
    let body: String
    let title: String
    let theme: Theme
    let baseURL: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = .windowBackgroundColor
        #if DEBUG
        webView.isInspectable = true
        #endif
        context.coordinator.webView = webView
        context.coordinator.show(body: body, title: title, theme: theme, baseURL: baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.show(body: body, title: title, theme: theme, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private struct Page: Equatable {
            let title: String
            let theme: Theme
            let baseURL: URL?
        }

        weak var webView: WKWebView?
        private var page: Page?
        private var currentBody: String?
        private var isLoading = false
        private var pendingBody: String?
        private var pendingScrollY: Double?

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
            webView.evaluateJavaScript(script, completionHandler: nil)
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
