# Uncial — Settings and first-run setup

Date: 2026-09-05
Status: approved by default (autonomous run; assumptions listed)
Builds on: `2026-09-05-uncial-design.md`

## Summary

Add a Settings window (⌘,) with three controls, and show the same controls in a
one-time Welcome window on the app's first launch:

| Setting | Options | Effect |
|---|---|---|
| Theme | System / Light / Dark | App windows and the rendered document switch immediately |
| Quick Look extension | Install / Remove | Registers and enables, or disables, `UncialQuickLook.appex` for the current user |
| Default app for Markdown | Make Default / Remove | Sets Uncial as the handler for `net.daringfireball.markdown`, or hands the role back |

The Welcome window appears only when `hasCompletedFirstRun` is unset. It offers
**Skip** and **Done**; both mark the first run complete. Closing the window does
too, so it never comes back on its own.

## Findings that shaped the design (probed on this machine)

- `pluginkit -m -i <id>` prints one line per registered copy, prefixed with the
  user election: `+` use, `-` ignore, ` ` (space) default, `!` debugger use,
  `=` superseded, `?` unknown. Nothing is printed when the extension is not
  registered. `pluginkit -e use|ignore|default -i <id>` changes the election;
  `pluginkit -a <appex>` registers, `-r` unregisters.
- `NSWorkspace.setDefaultApplication(at:toOpen:)` takes 7–8 seconds and shows
  no dialog for this UTI. Two calls in quick succession from one process made
  the second fail with `userCanceledErr` (-128). One change at a time, with a
  busy indicator, and one retry after a 1 s pause when the call fails.
- Setting `NSApp.appearance` re-themes all windows; `WKWebView` follows its
  `effectiveAppearance`, so `prefers-color-scheme` in the rendered page flips
  without reloading the HTML.

## Assumptions

1. "Install / remove the Quick Look extension" means the per-user election
   (what System Settings ▸ Extensions toggles), not copying files. Install =
   register the appex inside this app bundle + elect `use`; Remove = elect
   `ignore`. Both run `qlmanage -r` afterwards so Finder notices.
2. "Remove as default" restores the app that was default before Uncial took
   over (remembered in UserDefaults). If nothing is remembered, TextEdit becomes
   the default; there is no API to "unset" a handler.
3. Theme applies to the app. Quick Look previews keep following the system
   appearance; the sandboxed extension cannot read the app's preferences.
4. Preferences live in `UserDefaults.standard`: `theme` (String), `hasCompletedFirstRun`
   (Bool), `previousDefaultMarkdownApp` (String path).
5. First-run detection is per user account (UserDefaults). Reset for testing with
   `defaults delete com.maksimradaev.uncial hasCompletedFirstRun`.

## Components

### UncialCore additions (pure, `swift test`)

```swift
public enum QuickLookExtensionState: Equatable { case enabled, disabled, unregistered, unknown }

public enum QuickLookElection {
    /// Parses `pluginkit -m -i <id>` output. Empty → .unregistered; `-` → .disabled;
    /// `+`, ` `, `!`, `=` → .enabled; anything else → .unknown. First line wins.
    public static func parse(_ output: String) -> QuickLookExtensionState
}
```

### App additions

- `Theme` (`enum Theme: String, CaseIterable`): `system`, `light`, `dark`;
  `title`; `appearance: NSAppearance?` (nil / `.aqua` / `.darkAqua`).
- `AppSettings` (`@Observable @MainActor`, `shared`): `theme` (persists and
  applies `NSApp.appearance` in `didSet`), `hasCompletedFirstRun`,
  `markFirstRunCompleted()`, `applyTheme()`. Takes a `UserDefaults` for tests.
- `ShellCommand` (`nonisolated`): `run(_ executable: String, _ arguments: [String]) async throws -> String`
  via `Process` + `terminationHandler`; non-zero exit throws with the output.
- `QuickLookExtensionManager` (`@Observable @MainActor`, `shared`): `state`,
  `isBusy`, `errorMessage`; `refresh()`, `install()`, `remove()`. Uses
  `/usr/bin/pluginkit` and `/usr/bin/qlmanage`. Extension id
  `com.maksimradaev.uncial.QuickLook`, path `Bundle.main.builtInPlugInsURL/UncialQuickLook.appex`.
- `DefaultAppWorkspace` protocol (`defaultApplicationURL(for:)`,
  `setDefaultApplication(at:for:)`) with an `NSWorkspace` conformance whose
  setter retries once after 1 s (the deprecated LaunchServices C API would
  add a compiler warning for no extra robustness).
- `DefaultAppManager` (`@Observable @MainActor`, `shared`): `isDefault: Bool?`,
  `isBusy`, `errorMessage`, `currentDefaultName`; `refresh()`, `makeDefault()`,
  `removeDefault()`. Remembers the previous handler before taking over; restores
  it, else TextEdit (`/System/Applications/TextEdit.app`).
- `SettingsForm` (SwiftUI): three sections, shared by `SettingsView` (the
  `Settings` scene) and `WelcomeView`.
- `WelcomeView` + `WelcomeWindowController` (AppKit `NSWindow` hosting SwiftUI
  through `NSHostingController`), title "Welcome to Uncial", Skip / Done.
- `AppDelegate` (`NSApplicationDelegateAdaptor`): applies the theme in
  `applicationWillFinishLaunching`, shows the Welcome window in
  `applicationDidFinishLaunching` when `hasCompletedFirstRun` is false.

## UI

Settings window (⌘,), grouped form, ~480 pt wide:

```
Appearance
  Theme            [ System | Light | Dark ]

Quick Look
  ● Enabled — Space in Finder renders Markdown            [ Remove ]
  Uses the extension inside this copy of Uncial. Keep the app in /Applications.

Default app
  ● Uncial is the default app for Markdown files          [ Remove ]
  (or: ● Default app: Xcode                               [ Make Default ])
  Applies to .md, .markdown and related files.
```

Buttons show a spinner and disable while a change runs. Errors appear in red
below the affected row. Welcome window = app icon + title + one-line intro +
the same form + `Skip` / `Done` (default button).

## Error handling

| Situation | Behavior |
|---|---|
| `pluginkit` exits non-zero | Row shows the command's output in red; state re-read |
| Extension not registered and Install clicked | `-a` registers first, then `-e use` |
| `setDefaultApplication` throws | Retry once after 1 s; if that fails too, show the error |
| Previous default app no longer exists | Fall back to TextEdit |
| Settings opened from a build-dir copy | Works; caption reminds to keep the app in /Applications |

## Testing

- UncialCore: `QuickLookElection.parse` for empty, `-`, `+`, ` `, `?`, multi-line input.
- uncialTests (in-app host): `AppSettings` persistence + first-run flag with a
  private `UserDefaults` suite; `Theme.appearance` mapping; `DefaultAppManager`
  with a fake workspace (stores previous, restores previous, TextEdit fallback,
  `isDefault` detection); `ShellCommand` with `/bin/echo` and a failing command.
- Manual/scripted: `pluginkit` election round trip (done in probe);
  `NSWorkspace` round trip (done in probe); a scratch script proving
  `NSApp.appearance` flips `prefers-color-scheme` inside a `WKWebView`; launch
  with `hasCompletedFirstRun` cleared and confirm the Welcome window is created
  (log line at default level), then clear the flag again so the owner sees the
  Welcome on their first launch.

## Out of scope

Per-document theme, theming the Quick Look preview, a "show welcome again"
menu item, localization.
