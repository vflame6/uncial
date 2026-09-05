import SwiftUI
import WebKit

/// Shows rendered HTML. Content JavaScript is off; the document is untrusted input.
struct WebView: NSViewRepresentable {
    let html: String
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
        context.coordinator.show(html: html, baseURL: baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.show(html: html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        private var currentHTML: String?
        private var pendingScrollY: Double?

        func show(html: String, baseURL: URL?) {
            guard html != currentHTML, let webView else { return }
            let isFirstLoad = currentHTML == nil
            currentHTML = html
            if isFirstLoad {
                webView.loadHTMLString(html, baseURL: baseURL)
                return
            }
            webView.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
                self?.pendingScrollY = value as? Double
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let scrollY = pendingScrollY else { return }
            pendingScrollY = nil
            webView.evaluateJavaScript("window.scrollTo(0, \(scrollY));", completionHandler: nil)
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
