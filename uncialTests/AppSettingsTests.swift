import AppKit
import Testing
@testable import Uncial

@MainActor
@Suite struct AppSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "uncial-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToSystemThemeAndFirstRunPending() {
        let settings = AppSettings(defaults: freshDefaults(), applyAppearance: false)
        #expect(settings.theme == .system)
        #expect(settings.hasCompletedFirstRun == false)
    }

    @Test func persistsThemeAndFirstRun() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, applyAppearance: false)
        settings.theme = .dark
        settings.markFirstRunCompleted()
        let reloaded = AppSettings(defaults: defaults, applyAppearance: false)
        #expect(reloaded.theme == .dark)
        #expect(reloaded.hasCompletedFirstRun == true)
    }

    @Test func themeAppearanceMapping() {
        #expect(Theme.system.appearance == nil)
        #expect(Theme.light.appearance?.name == .aqua)
        #expect(Theme.dark.appearance?.name == .darkAqua)
    }
}
