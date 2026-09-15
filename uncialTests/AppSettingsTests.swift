import AppKit
import Testing
import UncialCore
@testable import Uncial

@MainActor
@Suite struct AppSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "uncial-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaults() {
        let settings = AppSettings(defaults: freshDefaults(), applyAppearance: false)
        #expect(settings.appearance == .system)
        #expect(settings.theme == .macOS)
        #expect(settings.defaultEditorMode == .split)
        #expect(settings.syncScrolling == true)
        #expect(settings.showLineNumbers == false)
        #expect(settings.autoPairing == true)
        #expect(settings.continueLists == true)
        #expect(settings.showStatusBar == false)
        #expect(settings.hasCompletedFirstRun == false)
    }

    @Test func persistsEditorConveniences() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, applyAppearance: false)
        settings.showLineNumbers = true
        settings.autoPairing = false
        settings.continueLists = false
        settings.showStatusBar = true
        let reloaded = AppSettings(defaults: defaults, applyAppearance: false)
        #expect(reloaded.showLineNumbers == true)
        #expect(reloaded.autoPairing == false)
        #expect(reloaded.continueLists == false)
        #expect(reloaded.showStatusBar == true)
    }

    @Test func persistsSyncScrollingOff() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, applyAppearance: false)
        settings.syncScrolling = false
        #expect(AppSettings(defaults: defaults, applyAppearance: false).syncScrolling == false)
    }

    @Test func persistsEverything() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, applyAppearance: false)
        settings.appearance = .dark
        settings.theme = .solarized
        settings.defaultEditorMode = .rawEditor
        settings.markFirstRunCompleted()
        let reloaded = AppSettings(defaults: defaults, applyAppearance: false)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.theme == .solarized)
        #expect(reloaded.defaultEditorMode == .rawEditor)
        #expect(reloaded.hasCompletedFirstRun == true)
    }

    @Test func migratesLegacyLivePreviewToSplit() {
        let defaults = freshDefaults()
        defaults.set("livePreview", forKey: "defaultEditorMode")
        let settings = AppSettings(defaults: defaults, applyAppearance: false)
        #expect(settings.defaultEditorMode == .split)
        #expect(defaults.string(forKey: "defaultEditorMode") == "split")
        settings.defaultEditorMode = .livePreview
        #expect(defaults.string(forKey: "defaultEditorMode") == "inlinePreview")
        #expect(AppSettings(defaults: defaults, applyAppearance: false).defaultEditorMode == .livePreview)
    }

    @Test func migratesLegacyThemeKeyToAppearance() {
        let defaults = freshDefaults()
        defaults.set("dark", forKey: "theme")
        let settings = AppSettings(defaults: defaults, applyAppearance: false)
        #expect(settings.appearance == .dark)
        #expect(settings.theme == .macOS)
        #expect(defaults.string(forKey: "appearance") == "dark")
        #expect(defaults.string(forKey: "theme") == nil)
        settings.theme = .github
        let reloaded = AppSettings(defaults: defaults, applyAppearance: false)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.theme == .github)
    }

    @Test func appearanceMapping() {
        #expect(Appearance.system.appearance == nil)
        #expect(Appearance.light.appearance?.name == .aqua)
        #expect(Appearance.dark.appearance?.name == .darkAqua)
    }
}
