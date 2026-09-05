import AppKit
import OSLog
import SwiftUI

/// One-time setup window. Leaving it in any way marks the first run complete.
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    static let shared = WelcomeWindowController()
    private static let logger = Logger(subsystem: "com.maksimradaev.uncial", category: "welcome")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Uncial"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: WelcomeView { [weak self] in self?.finish() })
    }

    required init?(coder: NSCoder) {
        fatalError("WelcomeWindowController does not support NSCoder")
    }

    func present() {
        Self.logger.notice("Presenting welcome window (first run)")
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        AppSettings.shared.markFirstRunCompleted()
    }

    private func finish() {
        AppSettings.shared.markFirstRunCompleted()
        close()
    }
}
