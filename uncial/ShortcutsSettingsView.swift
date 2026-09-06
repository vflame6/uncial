import SwiftUI

/// Shortcuts tab: a reference list generated from `AppShortcut`.
struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            ForEach(AppShortcut.sections, id: \.self) { section in
                Section(section) {
                    ForEach(AppShortcut.shortcuts(in: section)) { shortcut in
                        LabeledContent(shortcut.title) {
                            Text(shortcut.display)
                                .monospaced()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
