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

    @Test func attributionParsesAsMarkdown() throws {
        let text = try AttributedString(markdown: AppInfo.attribution)
        #expect(String(text.characters) == "Created by Maksim Radaev/@vflame6")
        let links = text.runs.compactMap(\.link)
        #expect(links == [URL(string: "https://github.com/vflame6")!])
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
