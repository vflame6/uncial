import AppKit
import Testing
@testable import Uncial

@MainActor
@Suite struct AboutPanelTests {
    @Test func creditsLinkTheHandle() {
        let credits = AboutPanel.credits()
        #expect(credits.string == "Created by Maksim Radaev/@vflame6")
        let handle = (credits.string as NSString).range(of: "@vflame6")
        var range = NSRange()
        let link = credits.attribute(.link, at: handle.location, effectiveRange: &range)
        #expect((link as? URL)?.absoluteString == "https://github.com/vflame6" || (link as? String) == "https://github.com/vflame6")
        #expect(range == handle)
        #expect(credits.attribute(.link, at: 0, effectiveRange: nil) == nil)
    }

    /// The About tab and panel show the README's attribution line.
    @Test func attributionIsTheReadmesLine() throws {
        let readme = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("README.md")
        let lines = try String(contentsOf: readme, encoding: .utf8).components(separatedBy: "\n")
        #expect(lines.contains(AppInfo.attribution))
    }

    @Test func panelShowsTheCredits() async throws {
        AboutPanel.show()
        try await Task.sleep(for: .milliseconds(300))
        func textViews(in view: NSView?) -> [NSTextView] {
            guard let view else { return [] }
            return (view as? NSTextView).map { [$0] } ?? [] + view.subviews.flatMap { textViews(in: $0) }
        }
        let panel = NSApp.windows.first { window in
            textViews(in: window.contentView).contains { $0.string.contains("Created by Maksim Radaev") }
        }
        #expect(panel != nil)
        panel?.close()
    }
}
