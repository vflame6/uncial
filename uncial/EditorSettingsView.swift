import SwiftUI

/// Editor tab: default mode, saving, status bar, source editor conveniences, Split View scroll sync and ratio.
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
                Text("Applies to documents you open next. Switch any window with \(EditorMode.allCases.map { "\($0.title) \($0.shortcut.display)" }.joined(separator: ", ")), or cycle with \(AppShortcut.toggleEditorMode.display).")
            }

            Section {
                Toggle("Save changes automatically", isOn: $settings.autosave)
            } header: {
                Text("Saving")
            } footer: {
                Text("Off, the file changes only when you save with \(AppShortcut.save.display), and closing a window, quitting or reloading with unsaved changes asks first. On, edits are written to the file half a second after you stop typing, without asking.")
            }

            Section {
                Toggle("Show status bar", isOn: $settings.showStatusBar)
            } header: {
                Text("Window")
            } footer: {
                Text("A footer with the current mode and the document's line, word and character counts. Markdown markers such as # and * are not words; spaces and line breaks count as characters.")
            }

            Section {
                Picker("Text size", selection: Binding(
                    get: { settings.textSize == nil ? 0 : 1 },
                    set: { settings.textSize = $0 == 0 ? nil : settings.effectiveTextSize }
                )) {
                    Text("System").tag(0)
                    Text("Custom").tag(1)
                }
                .pickerStyle(.segmented)
                if settings.textSize != nil {
                    Stepper("\(settings.effectiveTextSize) pt", value: Binding(
                        get: { settings.effectiveTextSize },
                        set: { settings.textSize = $0 }
                    ), in: AppSettings.textSizeRange)
                }
            } header: {
                Text("Text")
            } footer: {
                Text("The editor and the rendered page scale together, like zooming: \(AppShortcut.zoomIn.display) and \(AppShortcut.zoomOut.display) in the View menu change the size, \(AppShortcut.actualSize.display) returns to the system size. Quick Look always uses the system size.")
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

            Section {
                Toggle("Limit line width to a readable column", isOn: $settings.readableLineWidth)
            } header: {
                Text("Live Preview")
            } footer: {
                Text("Centers up to \(Int(InlineLayout.readableWidth)) points of text, like the rendered page. Split View and Raw Editor always use the full width.")
            }

            Section {
                Toggle("Sync scrolling between source and preview", isOn: $settings.syncScrolling)
                Slider(value: $settings.splitRatio, in: SplitLayout.ratioRange, step: SplitLayout.ratioStep) {
                    Text("Source pane width")
                } minimumValueLabel: {
                    Text(percent(SplitLayout.ratioRange.lowerBound))
                } maximumValueLabel: {
                    Text(percent(SplitLayout.ratioRange.upperBound))
                }
            } header: {
                Text("Split View")
            } footer: {
                Text("The source gets \(percent(settings.splitRatio)) of the width and the preview \(percent(1 - settings.splitRatio)) whenever a window enters Split View. Dragging the divider changes a window until it leaves Split View.")
            }
        }
        .formStyle(.grouped)
    }

    private func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}
