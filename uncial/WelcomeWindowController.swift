import AppKit
import OSLog
import SwiftUI

/// One-time setup window, opened in the middle of the screen over the launch Open panel. Leaving it in
/// any way marks the first run complete.
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    static let shared = WelcomeWindowController()
    private static let logger = Logger(subsystem: "com.maksimradaev.uncial", category: "welcome")

    init() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to Uncial"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        shouldCascadeWindows = false
        window.delegate = self
        let host = NSHostingController(rootView: WelcomeView { [weak self] in self?.finish() })
        window.contentViewController = host
        // The window takes the hosting view's initial zero frame as its content size; SwiftUI sizes the
        // view only on the next layout pass, after `present()` has placed the window. Size it now.
        window.setContentSize(host.view.fittingSize)
    }

    required init?(coder: NSCoder) {
        fatalError("WelcomeWindowController does not support NSCoder")
    }

    func present() {
        Self.logger.notice("Presenting welcome window (first run)")
        if let window, let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            window.setFrame(WindowPlacement.centered(window.frame.size, in: area), display: false)
        }
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
