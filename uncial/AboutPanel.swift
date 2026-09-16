import AppKit

/// Uncial ▸ About Uncial: the standard About panel with the author credited under the version.
enum AboutPanel {
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
    }

    /// `AppInfo.attribution` in the panel's small centered style, the handle a clickable link.
    static func credits() -> NSAttributedString {
        let markdown = (try? AttributedString(markdown: AppInfo.attribution)) ?? AttributedString(AppInfo.attribution)
        let credits = NSMutableAttributedString(markdown)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttributes([
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .paragraphStyle: paragraph,
        ], range: NSRange(location: 0, length: credits.length))
        return credits
    }
}
