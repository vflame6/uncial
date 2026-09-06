import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView(settings: .shared, quickLook: .shared, defaultApp: .shared)
                .tabItem { Label("General", systemImage: "gearshape") }
            EditorSettingsView(settings: .shared)
                .tabItem { Label("Editor", systemImage: "square.and.pencil") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480)
    }
}
