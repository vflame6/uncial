import AppKit
import UncialCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let openPanels = OpenPanelPlacement()

    /// `DocumentGroup(viewing:)` still lists a disabled stock "New" next to File ▸ New…; hide it.
    private func hideStockNewItem() {
        let selector = #selector(NSDocumentController.newDocument(_:))
        NSApp.mainMenu?.item(withTitle: "File")?.submenu?.items.first { $0.action == selector }?.isHidden = true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        openPanels.start()
        // Diagrams mermaid.js draws here are shared with Quick Look, which cannot run WebKit.
        DiagramWebRenderer.shared.store = DiagramStore.shared
        AppSettings.shared.applyAppearance()
        AppSettings.shared.publishTheme()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hideStockNewItem()
        if !AppSettings.shared.hasCompletedFirstRun {
            WelcomeWindowController.shared.present()
        }
    }

    /// Manually saved documents with unsaved edits get the Save / Cancel / Don't Save sheet, one window
    /// at a time; NSDocument knows nothing about those edits (see `DocumentWindowGuard`).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let pending = DocumentWindowGuard.needingReview
        guard !pending.isEmpty else { return .terminateNow }
        Task { @MainActor in
            sender.reply(toApplicationShouldTerminate: await DocumentWindowGuard.review(pending))
        }
        return .terminateLater
    }
}
