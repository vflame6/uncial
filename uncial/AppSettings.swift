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
        static let syncScrolling = "syncScrolling"
        static let showLineNumbers = "showLineNumbers"
        static let autoPairing = "autoPairing"
        static let continueLists = "continueLists"
        static let showStatusBar = "showStatusBar"
        static let readableLineWidth = "readableLineWidth"
        static let autosave = "autosave"
        static let externalChangePolicy = "externalChangePolicy"
        static let loadRemoteContent = "loadRemoteContent"
        static let splitRatio = "splitRatio"
        static let textSize = "textSize"
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
            publishShared()
        }
    }

    var defaultEditorMode: EditorMode {
        didSet { defaults.set(defaultEditorMode.rawValue, forKey: Key.defaultEditorMode) }
    }

    var syncScrolling: Bool {
        didSet { defaults.set(syncScrolling, forKey: Key.syncScrolling) }
    }

    var showLineNumbers: Bool {
        didSet { defaults.set(showLineNumbers, forKey: Key.showLineNumbers) }
    }

    var autoPairing: Bool {
        didSet { defaults.set(autoPairing, forKey: Key.autoPairing) }
    }

    var continueLists: Bool {
        didSet { defaults.set(continueLists, forKey: Key.continueLists) }
    }

    var showStatusBar: Bool {
        didSet { defaults.set(showStatusBar, forKey: Key.showStatusBar) }
    }

    var readableLineWidth: Bool {
        didSet { defaults.set(readableLineWidth, forKey: Key.readableLineWidth) }
    }

    /// Write edits to the file on their own shortly after typing pauses. Off (the default), the file
    /// changes only on File ▸ Save, and closing or quitting with unsaved edits asks first.
    var autosave: Bool {
        didSet { defaults.set(autosave, forKey: Key.autosave) }
    }

    /// What happens when the file changes on disk while a window holds unsaved edits.
    var externalChangePolicy: ExternalChangePolicy {
        didSet { defaults.set(externalChangePolicy.rawValue, forKey: Key.externalChangePolicy) }
    }

    /// Let documents load images and other files from the web. Off (the default), nothing is fetched
    /// on a document's behalf, in the window, in Live Preview or in Quick Look; links still open on a
    /// click. Shared with the Quick Look extension.
    var loadRemoteContent: Bool {
        didSet {
            defaults.set(loadRemoteContent, forKey: Key.loadRemoteContent)
            publishShared()
        }
    }

    /// Share of a Split View window's width for the source pane, within `SplitLayout.ratioRange`.
    var splitRatio: Double {
        didSet { defaults.set(splitRatio, forKey: Key.splitRatio) }
    }

    /// Custom body size in points, nil for the system size. Editor and rendered page scale from it.
    var textSize: Int? {
        didSet {
            if let textSize {
                defaults.set(textSize, forKey: Key.textSize)
            } else {
                defaults.removeObject(forKey: Key.textSize)
            }
        }
    }

    static let systemTextSize = 13
    static let textSizeRange = 9...36

    var effectiveTextSize: Int { textSize ?? Self.systemTextSize }
    /// 1 at the system size; the rendered page zooms by this.
    var textScale: Double { Double(effectiveTextSize) / Double(Self.systemTextSize) }

    func zoomIn() {
        textSize = min(effectiveTextSize + 1, Self.textSizeRange.upperBound)
    }

    func zoomOut() {
        textSize = max(effectiveTextSize - 1, Self.textSizeRange.lowerBound)
    }

    func resetTextSize() {
        textSize = nil
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
        // Before 2026-09-15 "livePreview" was the split mode; Live Preview now means the inline editor.
        if defaults.string(forKey: Key.defaultEditorMode) == EditorMode.legacySplitRawValue {
            defaults.set(EditorMode.split.rawValue, forKey: Key.defaultEditorMode)
        }
        defaultEditorMode = EditorMode(rawValue: defaults.string(forKey: Key.defaultEditorMode) ?? "") ?? .split
        syncScrolling = defaults.object(forKey: Key.syncScrolling) == nil ? true : defaults.bool(forKey: Key.syncScrolling)
        showLineNumbers = defaults.bool(forKey: Key.showLineNumbers)
        autoPairing = defaults.object(forKey: Key.autoPairing) == nil ? true : defaults.bool(forKey: Key.autoPairing)
        continueLists = defaults.object(forKey: Key.continueLists) == nil ? true : defaults.bool(forKey: Key.continueLists)
        showStatusBar = defaults.bool(forKey: Key.showStatusBar)
        readableLineWidth = defaults.object(forKey: Key.readableLineWidth) == nil ? true : defaults.bool(forKey: Key.readableLineWidth)
        autosave = defaults.bool(forKey: Key.autosave)
        externalChangePolicy = ExternalChangePolicy(rawValue: defaults.string(forKey: Key.externalChangePolicy) ?? "") ?? .ask
        loadRemoteContent = defaults.bool(forKey: Key.loadRemoteContent)
        splitRatio = SplitLayout.clamp(defaults.object(forKey: Key.splitRatio) as? Double ?? SplitLayout.defaultRatio)
        let storedSize = defaults.integer(forKey: Key.textSize)
        textSize = storedSize == 0 ? nil : min(max(storedSize, Self.textSizeRange.lowerBound), Self.textSizeRange.upperBound)
        hasCompletedFirstRun = defaults.bool(forKey: Key.hasCompletedFirstRun)
    }

    func markFirstRunCompleted() {
        hasCompletedFirstRun = true
        defaults.set(true, forKey: Key.hasCompletedFirstRun)
    }

    /// Hands the theme and the remote-content choice to the Quick Look extension through the App
    /// Group container. Best effort; only the real app instance does it (tests pass `applyAppearance: false`).
    func publishShared() {
        guard appliesAppearance, let directory = SharedSettings.containerURL() else { return }
        try? SharedSettings.write(theme: theme, remoteContent: loadRemoteContent, to: directory)
    }

    /// Re-themes every window. WKWebView follows its effective appearance, so rendered
    /// documents switch `prefers-color-scheme` without reloading.
    func applyAppearance() {
        guard appliesAppearance else { return }
        NSApp.appearance = appearance.appearance
    }
}
