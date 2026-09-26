import SwiftUI
import UncialCore

/// General tab: appearance, theme, Quick Look extension, default app, attachments, remote content. Also shown in the Welcome window.
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

            Section {
                TextField("Attachments folder", text: $settings.attachmentsDirectory, prompt: Text(AttachmentSearch.defaultDirectoryName))
                Toggle("Search the folders above the document", isOn: $settings.searchesParentsForAttachments)
                if settings.searchesParentsForAttachments {
                    Picker("Stop at", selection: $settings.attachmentSearchBoundary) {
                        ForEach(AttachmentSearch.Boundary.allCases, id: \.self) { boundary in
                            Text(boundary.title).tag(boundary)
                        }
                    }
                }
                if !settings.attachmentSearch.directoryName.isEmpty {
                    Picker("New attachments go to", selection: $settings.attachmentDestination) {
                        ForEach(AttachmentImporter.Destination.allCases, id: \.self) { destination in
                            Text(destination.title).tag(destination)
                        }
                    }
                }
            } header: {
                Text("Attachments")
            } footer: {
                Text(Self.attachmentsFooter(for: settings.attachmentSearch, destination: settings.attachmentDestination))
            }

            Section {
                Toggle("Load images and other files from the web", isOn: $settings.loadRemoteContent)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Off, a document's references to the web (images, media, style sheets) stay unloaded in the window, in Live Preview and in Quick Look, so opening a file tells no server about it. Links still open in your browser when you click them.")
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

    /// The Attachments footer: where a missing file is looked for and where pasted files go, for the chosen settings.
    static func attachmentsFooter(for search: AttachmentSearch, destination: AttachmentImporter.Destination) -> String {
        let name = search.directoryName.isEmpty ? nil : "“\(search.directoryName)”"
        let limit = search.boundary == .home ? "your home folder" : "the root of the disk"
        let lookup = switch (name, search.searchesParents) {
        case (let name?, true):
            "A missing image or linked file is looked for in the \(name) folder next to the document, then in the folders above it and their \(name) folders, up to \(limit)."
        case (let name?, false):
            "A missing image or linked file is looked for in the \(name) folder next to the document."
        case (nil, true):
            "A missing image or linked file is looked for in the folders above the document, up to \(limit)."
        case (nil, false):
            "A missing image or linked file is not looked for elsewhere."
        }
        // `AttachmentImporter` links a file the document reaches where it is and copies only the others.
        let others = switch (name, destination) {
        case (let name?, .nearestAttachmentsFolder) where search.searchesParents:
            "other files and pictures go to the first \(name) folder found above the document, or to one created next to it."
        case (let name?, .attachmentsFolder), (let name?, .nearestAttachmentsFolder):
            "other files and pictures go to the \(name) folder next to the document, created as needed."
        case (nil, _), (_, .documentFolder):
            "other files and pictures go next to the document."
        }
        return lookup + " Pasted or dropped files the document already reaches, such as those in its folder and other notes, are linked where they are; " + others
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
