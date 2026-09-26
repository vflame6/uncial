import AppKit
import Testing
import UncialCore
import WebKit
@testable import Uncial

/// Quick Look shows `MarkdownRenderer.renderDocument`'s HTML in WebKit with no content rule list.
@MainActor
@Suite(.serialized) struct QuickLookPageTests {
    /// With remote content off the page's own Content-Security-Policy keeps it off the web, even for
    /// references the sanitizer does not know (none of these went through it); without the policy
    /// the same page does reach the server.
    @Test func offlinePolicyKeepsThePageOffTheWeb() async throws {
        let listener = try LoopbackListener()
        await listener.start()
        defer { listener.stop() }
        let base = "http://127.0.0.1:\(listener.port)"
        let body = """
        <img src="\(base)/img.png">
        <table background="\(base)/table.png"><tr><td>x</td></tr></table>
        <div style="width: 10px; height: 10px; background-image: url('\(base)/style.png')"></div>
        <svg width="10" height="10"><image href="\(base)/svg.png" width="10" height="10"/></svg>
        <img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=">
        """
        try await load(HTMLDocument.wrap(body: body, title: "t", contentSecurityPolicy: HTMLDocument.offlinePolicy))
        #expect(listener.connections == 0)
        try await load(HTMLDocument.wrap(body: body, title: "t"))
        #expect(listener.connections > 0)
    }

    private func load(_ html: String) async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        defer { window.close() }
        webView.loadHTMLString(html, baseURL: nil)
        for _ in 0..<100 where webView.isLoading || webView.estimatedProgress < 1 {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(700))
    }
}
