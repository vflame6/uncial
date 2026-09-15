import AppKit

/// Moves every standalone Open panel to the middle of its screen. SwiftUI's document controller creates
/// the panels (at launch and for File ▸ Open…) and AppKit places each one above the middle right before
/// showing it, so the hook is that pre-show move: `NSWindow.didMoveNotification` while the panel is still
/// hidden. Moves of a visible panel are the user's and are left alone.
final class OpenPanelPlacement {
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let panel = note.object as? NSOpenPanel, !panel.isVisible,
                      let area = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
                let frame = WindowPlacement.centered(panel.frame.size, in: area)
                if panel.frame != frame {
                    panel.setFrame(frame, display: false)
                }
            }
        }
    }
}
