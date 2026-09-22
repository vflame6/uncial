import SwiftUI

/// The Settings window: General, Editor, Shortcuts, About. It opens on General every time: SwiftUI
/// would otherwise restore the last tab across launches (`com_apple_SwiftUI_Settings_selectedTabIndex`),
/// and the window is only hidden when closed, so the selection lives here and goes back to General as
/// the window closes.
struct SettingsView: View {
    enum Tab: CaseIterable {
        case general, editor, shortcuts, about
    }

    @State private var selection = Tab.general

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView(settings: .shared, quickLook: .shared, defaultApp: .shared)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            EditorSettingsView(settings: .shared)
                .tabItem { Label("Editor", systemImage: "square.and.pencil") }
                .tag(Tab.editor)
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(Tab.shortcuts)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .frame(width: 480)
        .background(WindowCloseObserver { selection = .general }.frame(width: 0, height: 0))
    }
}

/// Calls `onClose` when the window this view sits in closes.
struct WindowCloseObserver: NSViewRepresentable {
    let onClose: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        ObserverView()
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onClose = onClose
    }

    final class ObserverView: NSView {
        var onClose: () -> Void = {}

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
            guard let window else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window)
        }

        @objc private func windowWillClose(_ notification: Notification) {
            onClose()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
