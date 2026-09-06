import SwiftUI

/// Editor tab: which mode a document window starts in.
struct EditorSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Default mode", selection: $settings.defaultEditorMode) {
                    ForEach(EditorMode.allCases) { mode in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.title)
                            Text(mode.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Editing")
            } footer: {
                Text("Applies to documents you open next. Switch any window with \(AppShortcut.readOnly.display), \(AppShortcut.livePreview.display), \(AppShortcut.rawEditor.display), or cycle with \(AppShortcut.toggleEditorMode.display). Changes are saved to the file as you type.")
            }
        }
        .formStyle(.grouped)
    }
}
