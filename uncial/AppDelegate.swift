import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `DocumentGroup(viewing:)` still lists a disabled stock "New" next to File ▸ New…; hide it.
    private func hideStockNewItem() {
        let selector = #selector(NSDocumentController.newDocument(_:))
        NSApp.mainMenu?.item(withTitle: "File")?.submenu?.items.first { $0.action == selector }?.isHidden = true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppSettings.shared.applyAppearance()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hideStockNewItem()
        if !AppSettings.shared.hasCompletedFirstRun {
            WelcomeWindowController.shared.present()
        }
    }
}
