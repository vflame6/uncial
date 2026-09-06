import AppKit
import Observation
import UncialCore

@Observable
final class AppSettings {
    static let shared = AppSettings(defaults: .standard, applyAppearance: true)

    enum Key {
        static let appearance = "appearance"
        static let theme = "theme"
        static let defaultEditorMode = "defaultEditorMode"
        static let hasCompletedFirstRun = "hasCompletedFirstRun"
    }

    private let defaults: UserDefaults
    private let appliesAppearance: Bool

    var appearance: Appearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            applyAppearance()
        }
    }

    var theme: Theme {
        didSet {
            defaults.set(theme.rawValue, forKey: Key.theme)
            publishTheme()
        }
    }

    var defaultEditorMode: EditorMode {
        didSet { defaults.set(defaultEditorMode.rawValue, forKey: Key.defaultEditorMode) }
    }

    private(set) var hasCompletedFirstRun: Bool

    init(defaults: UserDefaults, applyAppearance: Bool) {
        self.defaults = defaults
        appliesAppearance = applyAppearance
        // Before 2026-09-06 the System/Light/Dark choice was stored under "theme".
        if defaults.string(forKey: Key.appearance) == nil,
           let legacy = Appearance(rawValue: defaults.string(forKey: Key.theme) ?? "") {
            defaults.set(legacy.rawValue, forKey: Key.appearance)
            defaults.removeObject(forKey: Key.theme)
        }
        appearance = Appearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        theme = Theme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .default
        defaultEditorMode = EditorMode(rawValue: defaults.string(forKey: Key.defaultEditorMode) ?? "") ?? .livePreview
        hasCompletedFirstRun = defaults.bool(forKey: Key.hasCompletedFirstRun)
    }

    func markFirstRunCompleted() {
        hasCompletedFirstRun = true
        defaults.set(true, forKey: Key.hasCompletedFirstRun)
    }

    /// Hands the theme to the Quick Look extension through the App Group container. Best effort;
    /// only the real app instance does it (tests pass `applyAppearance: false`).
    func publishTheme() {
        guard appliesAppearance, let directory = SharedSettings.containerURL() else { return }
        try? SharedSettings.write(theme: theme, to: directory)
    }

    /// Re-themes every window. WKWebView follows its effective appearance, so rendered
    /// documents switch `prefers-color-scheme` without reloading.
    func applyAppearance() {
        guard appliesAppearance else { return }
        NSApp.appearance = appearance.appearance
    }
}
