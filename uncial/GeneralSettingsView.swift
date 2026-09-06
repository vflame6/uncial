import SwiftUI
import UncialCore

/// General tab: appearance, theme, Quick Look extension, default app. Also shown in the Welcome window.
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
                Text("Uses the extension inside this copy of Uncial. Keep the app in /Applications.")
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
        case .enabled: "Enabled. Space in Finder renders Markdown."
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
