# Settings and First-Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Settings window (theme, Quick Look extension install/remove, default-app toggle) plus a one-time Welcome window that offers the same controls with Skip/Done.

**Architecture:** Pure parsing goes into `UncialCore`. Three small `@Observable` managers in the app own state and side effects (`NSApp.appearance`, `pluginkit`, `NSWorkspace`). One SwiftUI `SettingsForm` is shared by the `Settings` scene and an AppKit-hosted Welcome window shown from the app delegate on first launch.

**Tech Stack:** SwiftUI `Settings` scene, `NSApplicationDelegateAdaptor`, `NSHostingController`, `Process`, `NSWorkspace.setDefaultApplication`, `LSSetDefaultRoleHandlerForContentType`, Swift Testing.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-05-settings-first-run-design.md`.
- All `swift`/`xcodebuild` commands run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- App target: Swift 5 mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; mark non-UI helpers `nonisolated`.
- UserDefaults keys: `theme`, `hasCompletedFirstRun`, `previousDefaultMarkdownApp`.
- Extension id `com.maksimradaev.uncial.QuickLook`; tools `/usr/bin/pluginkit`, `/usr/bin/qlmanage`.
- Never leave the machine's default Markdown app or first-run flag changed after verification.

---

### Task 1: `QuickLookElection.parse` (UncialCore)

**Files:** Create `Packages/UncialCore/Sources/UncialCore/QuickLookElection.swift`; Test `Packages/UncialCore/Tests/UncialCoreTests/QuickLookElectionTests.swift`.

- [ ] **Step 1: Failing test**

```swift
import Testing
@testable import UncialCore

@Suite struct QuickLookElectionTests {
    @Test func emptyOutputMeansUnregistered() {
        #expect(QuickLookElection.parse("") == .unregistered)
        #expect(QuickLookElection.parse("\n") == .unregistered)
    }

    @Test func electionPrefixes() {
        #expect(QuickLookElection.parse("-    com.maksimradaev.uncial.QuickLook(1.0)\n") == .disabled)
        #expect(QuickLookElection.parse("+    com.maksimradaev.uncial.QuickLook(1.0)\n") == .enabled)
        #expect(QuickLookElection.parse("     com.maksimradaev.uncial.QuickLook(1.0)\n") == .enabled)
        #expect(QuickLookElection.parse("!    com.maksimradaev.uncial.QuickLook(1.0)\n") == .enabled)
        #expect(QuickLookElection.parse("=    com.maksimradaev.uncial.QuickLook(1.0)\n") == .enabled)
        #expect(QuickLookElection.parse("?    com.maksimradaev.uncial.QuickLook(1.0)\n") == .unknown)
    }

    @Test func firstLineWins() {
        #expect(QuickLookElection.parse("-    a(1.0)\n+    a(1.0)\n") == .disabled)
    }
}
```

- [ ] **Step 2: Run** `swift test` → "cannot find 'QuickLookElection'".

- [ ] **Step 3: Implement**

```swift
public enum QuickLookExtensionState: Equatable, Sendable {
    case enabled, disabled, unregistered, unknown
}

/// Interprets `pluginkit -m -i <identifier>` output.
public enum QuickLookElection {
    public static func parse(_ output: String) -> QuickLookExtensionState {
        guard let line = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).first,
              let prefix = line.first else { return .unregistered }
        switch prefix {
        case "-": return .disabled
        case "+", " ", "!", "=": return .enabled
        default: return .unknown
        }
    }
}
```

- [ ] **Step 4: Run** `swift test` → all pass.

---

### Task 2: `Theme`, `AppSettings`, `ShellCommand` (app) with unit tests

**Files:** Create `uncial/Theme.swift`, `uncial/AppSettings.swift`, `uncial/ShellCommand.swift`; Test `uncialTests/AppSettingsTests.swift`, `uncialTests/ShellCommandTests.swift`.

- [ ] **Step 1: Failing tests**

`uncialTests/AppSettingsTests.swift`:

```swift
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
```

`uncialTests/ShellCommandTests.swift`:

```swift
import Testing
@testable import Uncial

@Suite struct ShellCommandTests {
    @Test func capturesStandardOutput() async throws {
        let output = try await ShellCommand.run("/bin/echo", ["hello"])
        #expect(output == "hello\n")
    }

    @Test func nonZeroExitThrowsWithOutput() async {
        await #expect(throws: ShellCommand.Failure.self) {
            try await ShellCommand.run("/bin/sh", ["-c", "echo boom >&2; exit 3"])
        }
    }
}
```

- [ ] **Step 2: Run** `xcodebuild … test -only-testing:uncialTests` → compile errors for missing types.

- [ ] **Step 3: Implement**

`uncial/Theme.swift`:

```swift
import AppKit

enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil means "follow the system".
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
```

`uncial/AppSettings.swift`:

```swift
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

    /// Re-themes every window; WKWebView follows its effective appearance automatically.
    func applyTheme() {
        guard applyAppearance else { return }
        NSApp.appearance = theme.appearance
    }
}
```

`uncial/ShellCommand.swift`:

```swift
import Foundation

/// Runs a command-line tool and returns its combined output.
nonisolated enum ShellCommand {
    struct Failure: LocalizedError {
        let command: String
        let status: Int32
        let output: String

        var errorDescription: String? {
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "\(command) exited with status \(status)" : detail
        }
    }

    static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { process in
                let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let command = ([executable] + arguments).joined(separator: " ")
                    continuation.resume(throwing: Failure(command: command, status: process.terminationStatus, output: output))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

- [ ] **Step 4: Run** the unit tests → pass.

---

### Task 3: `QuickLookExtensionManager`

**Files:** Create `uncial/QuickLookExtensionManager.swift`. No unit test beyond the parser (side effects only); verified in Task 7.

```swift
import Foundation
import Observation
import UncialCore

@Observable
final class QuickLookExtensionManager {
    static let shared = QuickLookExtensionManager()

    static let extensionIdentifier = "com.maksimradaev.uncial.QuickLook"

    private(set) var state: QuickLookExtensionState = .unknown
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    private var appexURL: URL? {
        Bundle.main.builtInPlugInsURL?.appendingPathComponent("UncialQuickLook.appex")
    }

    func refresh() async {
        do {
            let output = try await ShellCommand.run("/usr/bin/pluginkit", ["-m", "-i", Self.extensionIdentifier])
            state = QuickLookElection.parse(output)
        } catch {
            state = .unknown
            errorMessage = error.localizedDescription
        }
    }

    /// Registers the appex inside this app bundle and elects it for use.
    func install() async {
        await perform {
            if let appexURL = self.appexURL {
                _ = try await ShellCommand.run("/usr/bin/pluginkit", ["-a", appexURL.path])
            }
            _ = try await ShellCommand.run("/usr/bin/pluginkit", ["-e", "use", "-i", Self.extensionIdentifier])
        }
    }

    /// Elects the extension to be ignored (same as switching it off in System Settings).
    func remove() async {
        await perform {
            _ = try await ShellCommand.run("/usr/bin/pluginkit", ["-e", "ignore", "-i", Self.extensionIdentifier])
        }
    }

    private func perform(_ work: @escaping @Sendable () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
            _ = try? await ShellCommand.run("/usr/bin/qlmanage", ["-r"])
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }
}
```

- [ ] **Step 1: Write it.** Build succeeds (Task 6 wires it into UI).

---

### Task 4: `DefaultAppManager` with fake-workspace tests

**Files:** Create `uncial/DefaultAppManager.swift`; Test `uncialTests/DefaultAppManagerTests.swift`.

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Uncial

@MainActor
final class FakeWorkspace: DefaultAppWorkspace {
    var current: URL?
    var setCalls: [URL] = []
    var failNext = false

    init(current: URL?) { self.current = current }

    func defaultApplicationURL(for type: UTType) -> URL? { current }

    func setDefaultApplication(at url: URL, for type: UTType) async throws {
        if failNext { failNext = false; throw CocoaError(.fileReadUnknown) }
        setCalls.append(url)
        current = url
    }
}

@MainActor
@Suite struct DefaultAppManagerTests {
    let uncial = URL(fileURLWithPath: "/Applications/Uncial.app")
    let xcode = URL(fileURLWithPath: "/Applications/Xcode.app")

    private func freshDefaults() -> UserDefaults {
        let name = "uncial-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func detectsWhetherUncialIsDefault() async {
        let workspace = FakeWorkspace(current: xcode)
        let manager = DefaultAppManager(workspace: workspace, ownURL: uncial, defaults: freshDefaults())
        await manager.refresh()
        #expect(manager.isDefault == false)
        #expect(manager.currentDefaultName == "Xcode")
        workspace.current = uncial
        await manager.refresh()
        #expect(manager.isDefault == true)
    }

    @Test func makeDefaultRemembersPreviousAndRemoveRestoresIt() async {
        let workspace = FakeWorkspace(current: xcode)
        let defaults = freshDefaults()
        let manager = DefaultAppManager(workspace: workspace, ownURL: uncial, defaults: defaults)
        await manager.makeDefault()
        #expect(workspace.setCalls == [uncial])
        #expect(manager.isDefault == true)
        await manager.removeDefault()
        #expect(workspace.setCalls == [uncial, xcode])
        #expect(manager.isDefault == false)
    }

    @Test func removeFallsBackToTextEditWithoutPrevious() async {
        let workspace = FakeWorkspace(current: uncial)
        let manager = DefaultAppManager(workspace: workspace, ownURL: uncial, defaults: freshDefaults())
        await manager.removeDefault()
        #expect(workspace.setCalls == [URL(fileURLWithPath: "/System/Applications/TextEdit.app")])
    }

    @Test func surfacesErrors() async {
        let workspace = FakeWorkspace(current: xcode)
        workspace.failNext = true
        let manager = DefaultAppManager(workspace: workspace, ownURL: uncial, defaults: freshDefaults())
        await manager.makeDefault()
        #expect(manager.errorMessage != nil)
        #expect(manager.isDefault == false)
    }
}
```

- [ ] **Step 2: Run** → compile errors.

- [ ] **Step 3: Implement**

```swift
import AppKit
import CoreServices
import Observation
import UniformTypeIdentifiers

@MainActor
protocol DefaultAppWorkspace: AnyObject {
    func defaultApplicationURL(for type: UTType) -> URL?
    func setDefaultApplication(at url: URL, for type: UTType) async throws
}

/// NSWorkspace-backed implementation; falls back to the LaunchServices C API when the modern call fails.
final class SystemWorkspace: DefaultAppWorkspace {
    func defaultApplicationURL(for type: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: type)
    }

    func setDefaultApplication(at url: URL, for type: UTType) async throws {
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: url, toOpen: type)
        } catch {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { throw error }
            let status = LSSetDefaultRoleHandlerForContentType(type.identifier as CFString, .all, bundleID as CFString)
            guard status == noErr else { throw error }
        }
    }
}

@Observable
final class DefaultAppManager {
    static let shared = DefaultAppManager(workspace: SystemWorkspace(), ownURL: Bundle.main.bundleURL, defaults: .standard)

    static let previousDefaultKey = "previousDefaultMarkdownApp"
    static let textEditURL = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

    private(set) var isDefault: Bool?
    private(set) var currentDefaultName: String?
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    private let workspace: DefaultAppWorkspace
    private let ownURL: URL
    private let defaults: UserDefaults

    init(workspace: DefaultAppWorkspace, ownURL: URL, defaults: UserDefaults) {
        self.workspace = workspace
        self.ownURL = ownURL
        self.defaults = defaults
    }

    func refresh() async {
        let current = workspace.defaultApplicationURL(for: .markdown)
        isDefault = current.map(isOwnApp) ?? false
        currentDefaultName = current?.deletingPathExtension().lastPathComponent
    }

    func makeDefault() async {
        await perform {
            if let current = self.workspace.defaultApplicationURL(for: .markdown), !self.isOwnApp(current) {
                self.defaults.set(current.path, forKey: Self.previousDefaultKey)
            }
            try await self.workspace.setDefaultApplication(at: self.ownURL, for: .markdown)
        }
    }

    func removeDefault() async {
        await perform {
            try await self.workspace.setDefaultApplication(at: self.restoreTarget(), for: .markdown)
        }
    }

    /// The remembered previous handler when it still exists and is not Uncial; otherwise TextEdit.
    func restoreTarget() -> URL {
        if let path = defaults.string(forKey: Self.previousDefaultKey) {
            let url = URL(fileURLWithPath: path)
            if !isOwnApp(url), FileManager.default.fileExists(atPath: path) || !path.hasPrefix("/Applications") {
                return url
            }
        }
        return Self.textEditURL
    }

    private func isOwnApp(_ url: URL) -> Bool {
        if let identifier = Bundle(url: url)?.bundleIdentifier, let own = Bundle(url: ownURL)?.bundleIdentifier {
            return identifier == own
        }
        return url.standardizedFileURL.path == ownURL.standardizedFileURL.path
    }

    private func perform(_ work: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }
}
```

Note on `restoreTarget`: the fake test uses `/Applications/Xcode.app`, which exists on this machine; the `fileExists` check is what makes a stale remembered path fall through to TextEdit. Keep the condition exactly: existing path → use it.

Simplify to:

```swift
    func restoreTarget() -> URL {
        if let path = defaults.string(forKey: Self.previousDefaultKey),
           FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            if !isOwnApp(url) { return url }
        }
        return Self.textEditURL
    }
```

- [ ] **Step 4: Run** unit tests → pass.

---

### Task 5: `SettingsForm`, `SettingsView`, `WelcomeView`, `WelcomeWindowController`, `AppDelegate`, `UncialApp` wiring

**Files:** Create `uncial/SettingsForm.swift`, `uncial/SettingsView.swift`, `uncial/WelcomeView.swift`, `uncial/WelcomeWindowController.swift`, `uncial/AppDelegate.swift`; Modify `uncial/uncialApp.swift`.

`uncial/SettingsForm.swift`:

```swift
import SwiftUI
import UncialCore

/// The three settings rows, shared by the Settings window and the Welcome window.
struct SettingsForm: View {
    @Bindable var settings: AppSettings
    var quickLook: QuickLookExtensionManager
    var defaultApp: DefaultAppManager

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(Theme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                LabeledContent {
                    ActionButton(title: quickLook.state == .enabled ? "Remove" : "Install", isBusy: quickLook.isBusy) {
                        Task { quickLook.state == .enabled ? await quickLook.remove() : await quickLook.install() }
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
                        Task { defaultApp.isDefault == true ? await defaultApp.removeDefault() : await defaultApp.makeDefault() }
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
        case .enabled: "Enabled — Space in Finder renders Markdown"
        case .disabled: "Disabled"
        case .unregistered: "Not installed"
        case .unknown: "Status unknown"
        }
    }

    private var defaultAppStatusText: String {
        switch defaultApp.isDefault {
        case true: "Uncial is the default app for Markdown files"
        case false: "Default app: \(defaultApp.currentDefaultName ?? "none")"
        default: "Checking…"
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
                ProgressView().controlSize(.small).frame(width: 80)
            } else {
                Text(title).frame(width: 80)
            }
        }
        .disabled(isBusy)
    }
}
```

`uncial/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        SettingsForm(settings: AppSettings.shared, quickLook: .shared, defaultApp: .shared)
            .frame(width: 480)
    }
}
```

`uncial/WelcomeView.swift`:

```swift
import SwiftUI

struct WelcomeView: View {
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Welcome to Uncial")
                    .font(.title.weight(.semibold))
                Text("Take a minute to set things up. Everything here can be changed later in Settings (⌘,).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.horizontal, 32)

            SettingsForm(settings: AppSettings.shared, quickLook: .shared, defaultApp: .shared)
                .scrollDisabled(true)

            HStack {
                Button("Skip", action: finish)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Done", action: finish)
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 520)
    }
}
```

`uncial/WelcomeWindowController.swift`:

```swift
import AppKit
import OSLog
import SwiftUI

/// One-time setup window. Any way of leaving it marks the first run complete.
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    static let shared = WelcomeWindowController()
    private static let logger = Logger(subsystem: "com.maksimradaev.uncial", category: "welcome")

    init() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to Uncial"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let hosting = NSHostingController(rootView: WelcomeView { [weak self] in self?.finish() })
        hosting.sizingOptions = [.preferredContentSize]
        window.contentViewController = hosting
    }

    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    func present() {
        Self.logger.notice("Presenting welcome window (first run)")
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        AppSettings.shared.markFirstRunCompleted()
    }

    private func finish() {
        AppSettings.shared.markFirstRunCompleted()
        close()
    }
}
```

`uncial/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppSettings.shared.applyTheme()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AppSettings.shared.hasCompletedFirstRun {
            WelcomeWindowController.shared.present()
        }
    }
}
```

`uncial/uncialApp.swift` — add the adaptor and the Settings scene:

```swift
import SwiftUI

@main
struct UncialApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @FocusedValue(\.reloadDocument) private var reloadDocument

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { configuration in
            DocumentView(document: configuration.document, fileURL: configuration.fileURL)
        }
        .defaultSize(width: 900, height: 760)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Reload") { reloadDocument?.run() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(reloadDocument == nil)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
```

- [ ] **Step 1: Write files, build** → `** BUILD SUCCEEDED **`, no warnings in project code.

---

### Task 6: Verification

- [ ] Scratch script: `NSApplication` + `WKWebView` loading `renderDocument("# x")`; toggle `NSApp.appearance` between aqua/darkAqua; `matchMedia('(prefers-color-scheme: dark)').matches` must follow.
- [ ] Unit tests: `swift test` (core) and `xcodebuild test -only-testing:uncialTests`.
- [ ] First run: `defaults delete com.maksimradaev.uncial hasCompletedFirstRun`; launch the Debug app with the sample file; `log show --predicate 'subsystem == "com.maksimradaev.uncial" AND category == "welcome"'` shows "Presenting welcome window"; quit; verify `defaults read … hasCompletedFirstRun` is now 1 (window close path); then `defaults delete … hasCompletedFirstRun` so the owner sees it once.
- [ ] Second launch (flag set) must not log the welcome line.
- [ ] Default app for Markdown must still be Xcode afterwards; the Quick Look election must be unchanged (extension unregistered until `make install`).

### Task 7: Docs and commit

- [ ] README: Settings section (theme, Quick Look install/remove, default app), first-run note, reset command.
- [ ] Commit on `settings-first-run`, fast-forward merge into `main`.

## Execution notes (2026-09-05)

- `LSSetDefaultRoleHandlerForContentType` fallback dropped (deprecation warning); `SystemWorkspace` retries the `NSWorkspace` call once after 1 s instead. Spec updated.
- Verified with a CGWindowList script (no Accessibility needed): first launch shows "Welcome to Uncial" (520×632) next to the document window; quitting marks the flag; second launch shows the document only. The flag was cleared afterwards so the owner sees the Welcome once.
- `defaults` resolves the bare domain to a stale sandbox container; the unsandboxed app reads `~/Library/Preferences/com.maksimradaev.uncial.plist`, so verification used the path form.
- `log` is a zsh builtin; use `/usr/bin/log show`.
- Launching the app re-registers the bundled Quick Look extension with LaunchServices automatically, so "unregistered until make install" cannot be maintained across test launches; the build-dir copies were unregistered at the very end.
