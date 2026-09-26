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
        AppSettings.shared.applyAppearance()
        // The unit tests run inside this app, under its bundle id: publishing from there would hand the
        // user's Quick Look extension the test build's settings and test diagrams.
        guard !Self.isTestHost(ProcessInfo.processInfo.environment) else { return }
        // Diagrams mermaid.js draws here are shared with Quick Look, which cannot run WebKit.
        DiagramWebRenderer.shared.store = DiagramStore.shared
        AppSettings.shared.publishShared()
    }

    /// `xcodebuild test` launches the app to host the unit tests, with the test bundle in its environment.
    nonisolated static func isTestHost(_ environment: [String: String]) -> Bool {
        environment["XCTestBundlePath"] != nil || environment["XCTestSessionIdentifier"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hideStockNewItem()
        if !AppSettings.shared.hasCompletedFirstRun {
            WelcomeWindowController.shared.present()
        }
    }

    /// Manually saved documents with unsaved edits get the Save / Cancel / Don't Save sheet, one window
    /// at a time; NSDocument knows nothing about those edits (see `DocumentWindowGuard`). Automatic
    /// saves run first, so one that fails (or meets a change on disk) is asked about too.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DocumentWindowGuard.flushAutomaticSaves()
        let pending = DocumentWindowGuard.needingReview
        guard !pending.isEmpty else { return .terminateNow }
        Task { @MainActor in
            sender.reply(toApplicationShouldTerminate: await DocumentWindowGuard.review(pending))
        }
        return .terminateLater
    }
}
