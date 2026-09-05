import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppSettings.shared.applyTheme()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AppSettings.shared.hasCompletedFirstRun {
            WelcomeWindowController.shared.present()
        }
    }
}
