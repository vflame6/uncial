import SwiftUI
import UncialCore

/// General tab: appearance, theme, remote content, attachments, Quick Look extension, default app. Also shown in the Welcome window.
struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    var quickLook: QuickLookExtensionManager
    var defaultApp: DefaultAppManager

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Theme", selection: $settings.theme) {
                    ForEach(Theme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
            }

            Section {
                Toggle("Load images and other files from the web", isOn: $settings.loadRemoteContent)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Off, a document's references to the web (images, media, style sheets) stay unloaded in the window, in Live Preview and in Quick Look, so opening a file tells no server about it. Links still open in your browser when you click them.")
            }

            Section {
                TextField("Attachments folder", text: $settings.attachmentsDirectory, prompt: Text(AttachmentSearch.defaultDirectoryName))
                Toggle("Search the folders above the document", isOn: $settings.searchesParentsForAttachments)
                Picker("Stop at", selection: $settings.attachmentSearchBoundary) {
                    ForEach(AttachmentSearch.Boundary.allCases, id: \.self) { boundary in
                        Text(boundary.title).tag(boundary)
                    }
                }
                .disabled(!settings.searchesParentsForAttachments)
            } header: {
                Text("Attachments")
            } footer: {
                Text("An image or linked file that is not where the document says is looked for in the attachments folder next to the document and then, folder by folder, above the document: in each folder itself and in its attachments folder, up to your home folder or the root of the disk. A document outside your home folder is searched in its own folder only while the search stops at home. Leave the folder name empty to look in the folders themselves only. Quick Look can read nothing but the document, so its previews show no attachments.")
            }

            Section {
                LabeledContent {
                    ActionButton(title: quickLook.state == .enabled ? "Remove" : "Install", isBusy: quickLook.isBusy) {
                        Task {
                            if quickLook.state == .enabled {
                                await quickLook.remove()
                            } else {
                                await quickLook.install()
                            }
                        }
                    }
                } label: {
                    StatusLabel(isOn: quickLook.state == .enabled, text: quickLookStatusText)
                }
                if let message = quickLook.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Quick Look")
            } footer: {
                Text("Previews with Space and thumbnails in Finder, Open panels and Get Info, rendered by the extensions inside this copy of Uncial. Keep the app in /Applications.")
            }

            Section {
                LabeledContent {
                    ActionButton(title: defaultApp.isDefault == true ? "Remove" : "Make Default", isBusy: defaultApp.isBusy) {
                        Task {
                            if defaultApp.isDefault == true {
                                await defaultApp.removeDefault()
                            } else {
                                await defaultApp.makeDefault()
                            }
                        }
                    }
                } label: {
                    StatusLabel(isOn: defaultApp.isDefault == true, text: defaultAppStatusText)
                }
                if let message = defaultApp.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Default app")
            } footer: {
                Text("Applies to .md, .markdown and related files. Changing the default can take a few seconds.")
            }
        }
        .formStyle(.grouped)
        .task {
            await quickLook.refresh()
            await defaultApp.refresh()
        }
    }

    private var quickLookStatusText: String {
        switch quickLook.state {
        case .enabled: "Enabled. Finder previews and thumbnails render Markdown."
        case .disabled: "Disabled"
        case .unregistered: "Not installed"
        case .unknown: "Status unknown"
        }
    }

    private var defaultAppStatusText: String {
        switch defaultApp.isDefault {
        case .some(true): "Uncial is the default app for Markdown files"
        case .some(false): "Default app: \(defaultApp.currentDefaultName ?? "none")"
        case .none: "Checking…"
        }
    }
}

private struct StatusLabel: View {
    let isOn: Bool
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "circle.fill")
                .foregroundStyle(isOn ? .green : .secondary)
                .imageScale(.small)
        }
    }
}

private struct ActionButton: View {
    let title: String
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isBusy {
                ProgressView().controlSize(.small).frame(width: 90)
            } else {
                Text(title).frame(width: 90)
            }
        }
        .disabled(isBusy)
    }
}
