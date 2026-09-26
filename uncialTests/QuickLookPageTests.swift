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

    /// The page follows the app's Light or Dark setting whatever the appearance of the view showing it
    /// (Quick Look's window), in every theme: the macOS theme's system colors through `color-scheme`,
    /// the others' dark values and the diagram's dark drawing through the fixed sheet. System follows the view.
    @Test func pageTakesTheAppsAppearanceOverItsWindows() async throws {
        let figure = "<figure class=\"mermaid\"><div class=\"light\">L</div><div class=\"dark\">D</div></figure>"
        for theme in Theme.allCases {
            for (window, appearance, dark) in [(NSAppearance.Name.aqua, PageAppearance.dark, true), (.darkAqua, .light, false),
                                               (.aqua, .system, false), (.darkAqua, .system, true)] {
                let html = HTMLDocument.wrap(body: figure, title: "t", theme: theme, appearance: appearance)
                let shown = try await evaluate(html, in: window, """
                [getComputedStyle(document.body).backgroundColor,
                 getComputedStyle(document.querySelector('figure .dark')).display].join('|')
                """)
                let parts = shown.split(separator: "|").map(String.init)
                let rgb = parts[0].split(whereSeparator: { !"0123456789.".contains($0) }).prefix(3).compactMap { Double($0) }
                #expect(rgb.count == 3 && (rgb.reduce(0, +) / 3 < 128) == dark, "\(theme) \(appearance) in \(window.rawValue): \(parts[0])")
                #expect((parts[1] != "none") == dark, "\(theme) \(appearance) in \(window.rawValue): diagram \(parts[1])")
            }
        }
    }

    private func evaluate(_ html: String, in appearance: NSAppearance.Name, _ script: String) async throws -> String {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        webView.appearance = NSAppearance(named: appearance)
        defer { window.close() }
        webView.loadHTMLString(html, baseURL: nil)
        for _ in 0..<100 where webView.isLoading || webView.estimatedProgress < 1 {
            try await Task.sleep(for: .milliseconds(50))
        }
        return try await webView.evaluateJavaScript(script) as? String ?? ""
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
