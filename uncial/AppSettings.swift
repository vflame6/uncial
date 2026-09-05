import AppKit
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings(defaults: .standard, applyAppearance: true)

    private enum Key {
        static let theme = "theme"
        static let hasCompletedFirstRun = "hasCompletedFirstRun"
    }

    private let defaults: UserDefaults
    private let applyAppearance: Bool

    var theme: Theme {
        didSet {
            defaults.set(theme.rawValue, forKey: Key.theme)
            applyTheme()
        }
    }

    private(set) var hasCompletedFirstRun: Bool

    init(defaults: UserDefaults, applyAppearance: Bool) {
        self.defaults = defaults
        self.applyAppearance = applyAppearance
        theme = Theme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        hasCompletedFirstRun = defaults.bool(forKey: Key.hasCompletedFirstRun)
    }

    func markFirstRunCompleted() {
        hasCompletedFirstRun = true
        defaults.set(true, forKey: Key.hasCompletedFirstRun)
    }

    /// Re-themes every window. WKWebView follows its effective appearance, so rendered
    /// documents switch `prefers-color-scheme` without reloading.
    func applyTheme() {
        guard applyAppearance else { return }
        NSApp.appearance = theme.appearance
    }
}
