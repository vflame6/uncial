import AppKit
import Testing
import UncialCore
import WebKit
@testable import Uncial

@MainActor
@Suite struct WebViewTests {
    @Test func blockerCompilesOnce() async {
        let first = await RemoteContentBlocker.shared.ruleList()
        let second = await RemoteContentBlocker.shared.ruleList()
        #expect(first != nil && first === second)
    }

    /// A document cannot send the view elsewhere: a meta refresh is cancelled and nothing opens.
    @Test func documentNavigationIsCancelled() async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let coordinator = WebView.Coordinator()
        coordinator.webView = webView
        webView.navigationDelegate = coordinator
        coordinator.show(body: "<meta http-equiv=\"refresh\" content=\"0;url=https://example.com/\"><p id=\"p\">stay</p>",
                         title: "t", theme: .macOS, baseURL: nil, remoteContent: true)
        try await Task.sleep(for: .seconds(2))
        #expect(webView.url?.absoluteString == "about:blank")
        let text = (try? await webView.evaluateJavaScript("document.getElementById('p') ? document.getElementById('p').innerText : ''") as? String) ?? ""
        #expect(text == "stay")
    }

    /// With the blocker installed the app's own page still loads, and inline (`data:`) images render.
    @Test func pageLoadsWithTheBlockerInstalled() async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let coordinator = WebView.Coordinator()
        coordinator.webView = webView
        webView.navigationDelegate = coordinator
        let pixel = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        coordinator.show(body: "<p id=\"p\">hello</p><img id=\"i\" src=\"\(pixel)\">", title: "t", theme: .macOS,
                         baseURL: FileManager.default.temporaryDirectory, remoteContent: false)
        var text = ""
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(100))
            let probe = "var p = document.getElementById('p'), i = document.getElementById('i'); p && i && i.complete ? p.innerText + '|' + i.naturalWidth : ''"
            text = (try? await webView.evaluateJavaScript(probe) as? String) ?? ""
            if !text.isEmpty { break }
        }
        #expect(text == "hello|1")
        #expect(webView.url?.scheme == "file")
    }
}
