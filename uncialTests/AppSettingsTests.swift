import AppKit
import Testing
import UncialCore
@testable import Uncial

@MainActor
@Suite final class AppSettingsTests {
    /// Every test's suites go with it, files included.
    private let suites = PreferenceSuites()
    deinit { suites.removeAll() }

    /// The settings as a launch reads them from `defaults`.
    private func loaded(from defaults: UserDefaults) -> AppSettings {
        AppSettings(defaults: defaults, applyAppearance: false)
    }

    @Test func defaults() {
        let settings = loaded(from: suites.make())
        #expect(settings.appearance == .system)
        #expect(settings.theme == .macOS)
        #expect(settings.defaultEditorMode == .split)
        #expect(settings.syncScrolling == true)
        #expect(settings.showLineNumbers == false)
        #expect(settings.autoPairing == true)
        #expect(settings.continueLists == true)
        #expect(settings.showStatusBar == false)
        #expect(settings.readableLineWidth == true)
        #expect(settings.autosave == false)
        #expect(settings.externalChangePolicy == .ask)
        #expect(settings.loadRemoteContent == true)
        #expect(settings.attachmentsDirectory == "attachments")
        #expect(settings.searchesParentsForAttachments == true)
        #expect(settings.attachmentSearchBoundary == .home)
        #expect(settings.attachmentSearch == AttachmentSearch())
        #expect(settings.attachmentDestination == .attachmentsFolder)
        #expect(settings.exportFormat == .pdf)
        #expect(settings.splitRatio == 0.5)
        #expect(settings.textSize == nil && settings.effectiveTextSize == 13 && settings.textScale == 1)
        #expect(settings.hasCompletedFirstRun == false)
    }

    /// Every choice made in Settings is there at the next launch.
    @Test func persistsEverySetting() {
        let defaults = suites.make()
        let settings = loaded(from: defaults)
        settings.appearance = .dark
        settings.theme = .solarized
        settings.defaultEditorMode = .rawEditor
        settings.syncScrolling = false
        settings.showLineNumbers = true
        settings.autoPairing = false
        settings.continueLists = false
        settings.showStatusBar = true
        settings.readableLineWidth = false
        settings.autosave = true
        settings.externalChangePolicy = .reload
        settings.loadRemoteContent = false
        settings.attachmentsDirectory = "assets"
        settings.searchesParentsForAttachments = false
        settings.attachmentSearchBoundary = .root
        settings.attachmentDestination = .nearestAttachmentsFolder
        settings.exportFormat = .html
        settings.splitRatio = 0.35
        settings.textSize = 20
        settings.markFirstRunCompleted()

        let reloaded = loaded(from: defaults)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.theme == .solarized)
        #expect(reloaded.defaultEditorMode == .rawEditor)
        #expect(reloaded.syncScrolling == false)
        #expect(reloaded.showLineNumbers == true)
        #expect(reloaded.autoPairing == false)
        #expect(reloaded.continueLists == false)
        #expect(reloaded.showStatusBar == true)
        #expect(reloaded.readableLineWidth == false)
        #expect(reloaded.autosave == true)
        #expect(reloaded.externalChangePolicy == .reload)
        #expect(reloaded.loadRemoteContent == false)
        #expect(reloaded.attachmentSearch == AttachmentSearch(directoryName: "assets", searchesParents: false, boundary: .root))
        #expect(reloaded.attachmentDestination == .nearestAttachmentsFolder)
        #expect(reloaded.exportFormat == .html)
        #expect(reloaded.splitRatio == 0.35)
        #expect(reloaded.textSize == 20)
        #expect(reloaded.hasCompletedFirstRun == true)
    }

    /// A stored value this version cannot use (another version's, a hand edit) falls back to the default,
    /// and a number out of range is clamped.
    @Test func unusableStoredValuesFallBack() {
        let defaults = suites.make()
        for key in [AppSettings.Key.externalChangePolicy, AppSettings.Key.attachmentSearchBoundary, AppSettings.Key.attachmentDestination, AppSettings.Key.exportFormat, "splitRatio"] {
            defaults.set("bogus", forKey: key)
        }
        defaults.set(0, forKey: "textSize")
        let bogus = loaded(from: defaults)
        #expect(bogus.externalChangePolicy == .ask)
        #expect(bogus.attachmentSearchBoundary == .home)
        #expect(bogus.attachmentDestination == .attachmentsFolder)
        #expect(bogus.exportFormat == .pdf)
        #expect(bogus.splitRatio == 0.5)
        #expect(bogus.textSize == nil)
        defaults.set(0.95, forKey: "splitRatio")
        defaults.set(100, forKey: "textSize")
        let large = loaded(from: defaults)
        #expect(large.splitRatio == 0.8)
        #expect(large.textSize == 36)
    }

    @Test func zoomsTheTextSizeWithinBounds() {
        let defaults = suites.make()
        let settings = loaded(from: defaults)
        settings.zoomIn()
        #expect(settings.textSize == 14 && settings.effectiveTextSize == 14)
        settings.zoomOut()
        settings.zoomOut()
        #expect(settings.textSize == 12)
        settings.textSize = 36
        settings.zoomIn()
        #expect(settings.textSize == 36)
        settings.textSize = 9
        settings.zoomOut()
        #expect(settings.textSize == 9)
        settings.resetTextSize()
        #expect(settings.textSize == nil && loaded(from: defaults).textSize == nil)
    }

    @Test func migratesLegacyLivePreviewToSplit() {
        let defaults = suites.make()
        defaults.set("livePreview", forKey: "defaultEditorMode")
        let settings = loaded(from: defaults)
        #expect(settings.defaultEditorMode == .split)
        #expect(defaults.string(forKey: "defaultEditorMode") == "split")
        settings.defaultEditorMode = .livePreview
        #expect(defaults.string(forKey: "defaultEditorMode") == "inlinePreview")
        #expect(loaded(from: defaults).defaultEditorMode == .livePreview)
    }

    @Test func migratesLegacyThemeKeyToAppearance() {
        let defaults = suites.make()
        defaults.set("dark", forKey: "theme")
        let settings = loaded(from: defaults)
        #expect(settings.appearance == .dark)
        #expect(settings.theme == .macOS)
        #expect(defaults.string(forKey: "appearance") == "dark")
        #expect(defaults.string(forKey: "theme") == nil)
        settings.theme = .github
        let reloaded = loaded(from: defaults)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.theme == .github)
    }

    @Test func appearanceMapping() {
        #expect(Appearance.system.appearance == nil)
        #expect(Appearance.light.appearance?.name == .aqua)
        #expect(Appearance.dark.appearance?.name == .darkAqua)
        // What Quick Look gets through the App Group.
        #expect(Appearance.allCases.map(\.pageAppearance) == [.system, .light, .dark])
    }
}
