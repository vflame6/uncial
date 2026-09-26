import AppKit
import Testing
import UncialCore
@testable import Uncial

@MainActor
@Suite final class AppSettingsTests {
    /// Every test's suites go with it, files included.
    private let suites = PreferenceSuites()
    deinit { suites.removeAll() }

    private func freshDefaults() -> UserDefaults { suites.make() }

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
        #expect(settings.readableLineWidth == true)
        #expect(settings.autosave == false)
        #expect(settings.externalChangePolicy == .ask)
        #expect(settings.loadRemoteContent == true)
        #expect(settings.attachmentsDirectory == "attachments")
        #expect(settings.searchesParentsForAttachments == true)
        #expect(settings.attachmentSearchBoundary == .home)
        #expect(settings.attachmentSearch == AttachmentSearch())
        #expect(settings.attachmentDestination == .attachmentsFolder)
        #expect(settings.splitRatio == 0.5)
        #expect(settings.textSize == nil && settings.effectiveTextSize == 13 && settings.textScale == 1)
        #expect(settings.hasCompletedFirstRun == false)
    }

    @Test func persistsRemoteContentAndExternalChangePolicy() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, applyAppearance: false)
        settings.loadRemoteContent = false
        settings.externalChangePolicy = .reload
        let reloaded = AppSettings(defaults: defaults, applyAppearance: false)
        #expect(reloaded.loadRemoteContent == false)
        #expect(reloaded.externalChangePolicy == .reload)
        defaults.set("bogus", forKey: AppSettings.Key.externalChangePolicy)
        #expect(AppSettings(defaults: defaults, applyAppearance: false).externalChangePolicy == .ask)
        #expect(ExternalChangePolicy.allCases.map(\.title) == ["Ask", "Keep my edits", "Reload the file"])
    }

    @Test func persistsAttachmentSearch() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, applyAppearance: false)
        settings.attachmentsDirectory = "assets"
        settings.searchesParentsForAttachments = false
        settings.attachmentSearchBoundary = .root
        settings.attachmentDestination = .nearestAttachmentsFolder
        let reloaded = AppSettings(defaults: defaults, applyAppearance: false)
        #expect(reloaded.attachmentsDirectory == "assets")
        #expect(reloaded.searchesParentsForAttachments == false)
        #expect(reloaded.attachmentSearchBoundary == .root)
        #expect(reloaded.attachmentDestination == .nearestAttachmentsFolder)
        #expect(reloaded.attachmentSearch == AttachmentSearch(directoryName: "assets", searchesParents: false, boundary: .root))
        defaults.set("bogus", forKey: AppSettings.Key.attachmentSearchBoundary)
        defaults.set("bogus", forKey: AppSettings.Key.attachmentDestination)
        #expect(AppSettings(defaults: defaults, applyAppearance: false).attachmentSearchBoundary == .home)
        #expect(AppSettings(defaults: defaults, applyAppearance: false).attachmentDestination == .attachmentsFolder)
        #expect(AttachmentSearch.Boundary.allCases.map(\.title) == ["Home folder", "System root"])
        #expect(AttachmentImporter.Destination.allCases.map(\.title) == ["Attachments folder next to the document", "First attachments folder found above", "The document's folder"])
    }

    @Test func persistsEditorConveniences() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, applyAppearance: false)
        settings.showLineNumbers = true
        settings.autoPairing = false
        settings.continueLists = false
        settings.showStatusBar = true
        settings.readableLineWidth = false
        let reloaded = AppSettings(defaults: defaults, applyAppearance: false)
        #expect(reloaded.showLineNumbers == true)
        #expect(reloaded.autoPairing == false)
        #expect(reloaded.continueLists == false)
        #expect(reloaded.showStatusBar == true)
        #expect(reloaded.readableLineWidth == false)
    }

    @Test func persistsAndClampsTheSplitRatio() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, applyAppearance: false)
        settings.splitRatio = 0.35
        #expect(AppSettings(defaults: defaults, applyAppearance: false).splitRatio == 0.35)
        defaults.set(0.95, forKey: "splitRatio")
        #expect(AppSettings(defaults: defaults, applyAppearance: false).splitRatio == 0.8)
        defaults.set("wide", forKey: "splitRatio")
        #expect(AppSettings(defaults: defaults, applyAppearance: false).splitRatio == 0.5)
    }

    @Test func zoomsTheTextSizeWithinBounds() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, applyAppearance: false)
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
        #expect(AppSettings(defaults: defaults, applyAppearance: false).textSize == 9)
        settings.resetTextSize()
        #expect(settings.textSize == nil && AppSettings(defaults: defaults, applyAppearance: false).textSize == nil)
        defaults.set(100, forKey: "textSize")
        #expect(AppSettings(defaults: defaults, applyAppearance: false).textSize == 36)
        defaults.set(0, forKey: "textSize")
        #expect(AppSettings(defaults: defaults, applyAppearance: false).textSize == nil)
    }

    @Test func persistsAutosave() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, applyAppearance: false)
        settings.autosave = true
        #expect(AppSettings(defaults: defaults, applyAppearance: false).autosave == true)
        settings.autosave = false
        #expect(AppSettings(defaults: defaults, applyAppearance: false).autosave == false)
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
