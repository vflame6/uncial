import SwiftUI

/// Editor tab: default mode, status bar, source editor conveniences, Split View scroll sync.
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
                Text("Applies to documents you open next. Switch any window with \(EditorMode.allCases.map { "\($0.title) \($0.shortcut.display)" }.joined(separator: ", ")), or cycle with \(AppShortcut.toggleEditorMode.display). Changes are saved to the file as you type.")
            }

            Section {
                Toggle("Show status bar", isOn: $settings.showStatusBar)
            } header: {
                Text("Window")
            } footer: {
                Text("A footer with the current mode and the document's line, word and character counts. Markdown markers such as # and * are not words; spaces and line breaks count as characters.")
            }

            Section {
                Toggle("Show line numbers", isOn: $settings.showLineNumbers)
                Toggle("Close brackets, quotes and Markdown markers automatically", isOn: $settings.autoPairing)
                Toggle("Continue lists and quotes on Return", isOn: $settings.continueLists)
            } header: {
                Text("Source")
            } footer: {
                Text("Typing ( [ { ` * _ or \" inserts the closing character after the cursor; typing it again skips over it, Backspace inside an empty pair removes both, and a selection gets wrapped. Press Return between ``` and ``` to start a code block. Return inside a list item or quote starts the next one; Return on an empty item ends it. Line numbers show in the source and, as source lines, in the rendered page.")
            }

            Section("Split View") {
                Toggle("Sync scrolling between source and preview", isOn: $settings.syncScrolling)
            }
        }
        .formStyle(.grouped)
    }
}
