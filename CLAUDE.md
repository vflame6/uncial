# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Uncial is a native macOS Markdown reader and editor (SwiftUI document app) with a bundled
Quick Look Preview Extension. One Swift package renders Markdown to a self-contained HTML page
in one of three themes; the app shows it in a `WKWebView`, offers an `NSTextView` editor beside
it (Read Only / Live Preview / Raw Editor) with Markdown coloring, scroll sync, optional line
numbers, auto-closing pairs, a find/replace bar and an optional status bar, writes edits through to the file, and
re-renders on disk changes; the extension returns the same HTML, in
the theme the app published to the App Group container, to Quick Look. Design specs and implementation plans (with execution notes) are local
working notes under `docs/superpowers/`, which is gitignored; they exist only on this machine.

## Toolchain rule

`xcode-select` on this machine points at the Command Line Tools, which lack `xcodebuild` and
the Swift `Testing` module. Every `swift` and `xcodebuild` invocation needs
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the Makefile exports it). Do not
run `xcode-select -s`.

## Commands

```sh
make core-test        # swift test in Packages/UncialCore (fast, no app host)
make test             # core tests + app unit tests (xcodebuild, target uncialTests)
make build            # Release build into ./build (CONFIG=Debug for Debug)
make install          # copy Uncial.app to /Applications, launch once, reset Quick Look
make icon             # regenerate AppIcon PNGs via scripts/make-icon.swift
make clean
```

Single tests (Swift Testing everywhere):

```sh
# package: --filter is a regex over "Suite/test"
cd Packages/UncialCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter 'HeadingAnchorsTests/slugFollowsGitHubRules'

# app target
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project uncial.xcodeproj \
  -scheme uncial -configuration Debug -derivedDataPath build test \
  -only-testing:uncialTests/DefaultAppManagerTests/surfacesErrors
```

Run a build without installing: `open -a build/Build/Products/Debug/Uncial.app path/to/file.md`.
Launching the app registers its Quick Look extension with LaunchServices; the build-dir copy
then competes with `/Applications/Uncial.app`. `pluginkit -r <appex>` removes a registration.

## Architecture

Three build products, one rendering pipeline:

| Part | Target / path | Notes |
|---|---|---|
| `UncialCore` | `Packages/UncialCore` (local SwiftPM, Swift 6 mode, Foundation only, no AppKit) | Rendering pipeline, `Theme` + `Stylesheet`, `SourcePositions`, `SharedSettings`, `FileWatcher`, `QuickLookElection` parser. Depends on `swiftlang/swift-cmark` branch `gfm`. |
| `Uncial.app` | target `uncial`, sources in `uncial/` | SwiftUI `DocumentGroup(viewing:)`; editing is owned by `DocumentViewModel`, not by NSDocument (see App flow). |
| `UncialQuickLook.appex` | target `UncialQuickLook`, sources in `UncialQuickLook/` | Data-based `QLPreviewProvider` returning HTML via `QLPreviewReply`. |

**Rendering pipeline** (`MarkdownRenderer.renderBody(_:baseURL:)`): `FrontMatter.split` →
`GFMRenderer` (cmark-gfm with table, strikethrough, autolink, tagfilter, tasklist; options
`UNSAFE | FOOTNOTES | VALIDATE_UTF8`) → `HTMLFixups.repairFootnoteBackrefs` (swift-cmark emits an
unterminated `aria-label` on the first footnote back-reference) → `HeadingAnchors.addIDs`
(GitHub slug rules, `-1`/`-2` dedupe) → front-matter block prepended → `ImageInliner`
(local `<img src>` of image MIME types → `data:` URIs, resolved against the document's
directory). With `sourcePositions: true` (the app's editor) cmark adds `data-sourcepos`
line ranges to block elements, shifted by `FrontMatter.bodyLineOffset` so they match the
editor's lines (`SourcePositions.shift`), and `SourcePositions.annotate` then adds `data-line`
(the first source line) to every block that starts a new line — never `pre`, `tr`, `td`, `th`,
one label per distinct line in document order — and wraps each code-block line in
`<span class="line" data-line="N">` (fenced blocks start after the fence; only their range spans
more lines than they have code lines). Quick Look leaves it off. `renderDocument(_:title:baseURL:theme:)`
wraps that fragment with `HTMLDocument.wrap(body:title:theme:)`, which inlines
`Stylesheet.css(for:)` and stamps `<html data-theme="…">`.

**Themes** (`Theme`: `macOS` default, `github`, `solarized`; `Stylesheet`): one base sheet of
layout/element rules written against custom properties (`--bg --fg --heading --muted --border
--border-muted --accent --code-bg --code-fg --row-alt --mark --quote-border --font-body
--font-mono --font-size --line-height --content-width --radius --heading-weight --h1…h6-size
--h1-border --h2-border`), plus one block per theme in `Themes/` that sets the light values on
`:root`, the dark values under `@media (prefers-color-scheme: dark)`, and any element
overrides. The macOS theme uses WebKit's `-apple-system-*` keywords (`-label`,
`-secondary-label`, `-text-background`, `-separator`, `-grid`, `-blue`,
`-odd-alternating-content-background`, `-find-highlight-background`), which resolve per the
view's effective appearance; custom properties cannot carry parse-time fallbacks, so there are
none. `Theme.editorPalette` (0xRRGGBB `background/foreground/accent/muted/code`, nil for macOS =
system colors via `EditorStyle`) colors the editor and its Markdown highlighting.

**No page JavaScript.** Quick Look executes no scripts in HTML previews and the app's
`WKWebView` has `allowsContentJavaScript = false` (Markdown is untrusted input). The HTML
contains no scripts; any post-processing happens in Swift on the HTML string. Only
app-authored scripts run, and `allowsContentJavaScript = false` does not stop them: through
`evaluateJavaScript`, reading/restoring `window.scrollY` around a full reload, replacing
`article.markdown-body`'s `innerHTML` (string literal built by `JavaScriptLiteral`) and
`PreviewScripts.scrollToLine`; and one `WKUserScript`, `PreviewScripts.observer`, which posts
the source line at the viewport top to the `uncialScroll` message handler on every scroll
(verified on macOS 26). Page content cannot run scripts, so it cannot touch the observer. The
CSS is a Swift string literal on purpose: no resource bundle to ship into the extension.
Light/dark is pure CSS (`prefers-color-scheme`); the app's Appearance setting works by setting
`NSApp.appearance`, which `WKWebView` and `ThemedTextView` follow without reloading.

**App flow:** `DocumentGroup(viewing:)` → `DocumentView` (per-window `EditorMode` state;
`HSplitView` of `MarkdownTextView` and/or the preview; toolbar segmented picker; focused values
`reloadDocument`, `saveDocument`, `editorMode`) → `DocumentViewModel`, which owns the editor
`text`, the rendered `body` (rendered off the main actor in `Task.detached`, stale results
dropped with a generation counter) and the write path: `updateText` re-renders after 150 ms and
saves after 500 ms (atomic write); `saveNow` runs on ⌘S, when leaving an editing mode,
`onDisappear`, and `NSApplication.willTerminateNotification`. A `FileWatcher` feeds
`syncFromDisk`, which applies `DiskSync.decide(disk:text:diskText:)`: `ignore` (our own write),
`adopt` (no local edits), `keepLocal` (local edits pending; the scheduled save overwrites).
`reload()` (⌘R) always adopts the disk text. NSDocument never writes: the stock Save/Save
As/Duplicate/Rename/Revert items are replaced in `uncialApp` (Close, Close All, Save), and
`AppDelegate` hides the disabled stock "New" next to File ▸ New… (`NewDocumentCommand`: save
panel, empty file, open). NSDocument must also never *think* it has changes: `ThemedTextView`
owns its `UndoManager` (overriding `undoManager`, handling `undo:`/`redo:` itself), because the
window's manager is NSDocument's and every registered edit would count as a change, start an
autosave and hit NSDocument's "changed by another application" check after the model's own
write (probed 2026-09-08: error 67000); `DocumentViewModel.saveNow` also refreshes the
NSDocument's `fileModificationDate` after each write so that check never trips. `WebView` reloads only when title/theme/baseURL change (scroll kept)
and otherwise swaps the body in place; a body arriving mid-load is applied in `didFinish`.
`MarkdownTextView` wraps `ThemedTextView` (TextKit 1 on purpose: `NSLayoutManager` does the
glyph ↔ point ↔ line math; `allowsNonContiguousLayout` on; SF Mono 13, soft wrap, smart
substitutions off, spell check on, find bar, undo); `updateNSView` replaces the string only
when it differs from the model and then clears undo. After every edit `rehighlight()` resets
the base attributes and applies `MarkdownHighlighter.spans(in:)` (pure, tested: fence and
front-matter state, inline code masked before emphasis/links) with `EditorStyle` attributes;
attribute-only, so undo is untouched; skipped above 200 000 characters. **Scroll sync** (Live
Preview only, `AppSettings.syncScrolling`): `ScrollSyncController` (pure, tested) turns
"editor scrolled to line L" into a `ScrollTarget` for the preview and vice versa, ignoring the
driven pane's echo for 300 ms; lines are 1-based fractional document lines, cmark's
`data-sourcepos` unit (`ThemedTextView.visibleTopLine()` is 0-based, `MarkdownTextView`
converts). The editor reports through the clip view's bounds-changed notification (skipped
while `isProgrammaticScroll`), the preview through the observer user script; `WebView`
re-applies its last target after every body swap so typing keeps the panes aligned. Link
policy in `WebView` is unchanged: same-document fragments allowed, everything else cancelled
and routed through `LinkOpener`. Keyboard shortcuts live in one table, `AppShortcut` (menus
bind from it; the Shortcuts tab lists it).

**Editor conveniences.** *Line numbers* (`AppSettings.showLineNumbers`): `LineNumberRulerView`,
an `NSRulerView` installed once per editor as the scroll view's vertical ruler (`rulersVisible`
follows the setting), numbers the first line fragment of every logical line from the layout
manager (`ThemedTextView.lineIndex`), caret line in the foreground color, the rest muted, width
from `GutterMetrics` (pure); `rehighlight()` calls its `invalidate()`. The rendered page shows
the same numbers: `HTMLDocument.wrap(lineNumbers:)` sets `class="line-numbers"` on `<html>`,
`WebView` toggles that class in place (`setLineNumbers`, re-applied in `didFinish`), and the
base stylesheet draws `attr(data-line)` as an absolutely positioned `::before` in the
article's left padding (`html.line-numbers .markdown-body`), 85% mono, one line box per label;
code-line spans inherit the code line height. *Auto-pairing* (`AppSettings.autoPairing`):
`AutoPairing` (pure, tested) turns a keystroke into an `Edit` — close `( [ { ` * _ "` in front
of whitespace, punctuation or a closer (markers only at word boundaries; `~` only at a line
start, `Pair.lineStartOnly`), skip a tracked closer, grow `*|*` → `**|**` up to three, wrap a
selection (also `< '`), drop the closer of an empty `*`/`_`/`~` pair before a space or Return,
Return inside ```` ```|``` ```` or `~~~|~~~` makes a fence (checked before the whitespace
rule), Backspace removes one layer of an empty pair — and tracks the pairs it inserted.
*List continuation* (`AppSettings.continueLists`): `ListContinuation.edit(in:at:)` (pure,
tested; `NSString.lineRange`, one regex for quote prefixes + indentation + bullet/number +
task box) runs in `insertNewline` after the pairing rules: it repeats the prefix on the next
line (numbers incremented, boxes unchecked, text after the caret carried along) or, on an
empty item, removes the marker; tracked pairs are mapped through the edit first. `ThemedTextView` overrides `insertText(_:replacementRange:)`,
`insertNewline`, `deleteBackward`, applies an `Edit` through `insertText(_:replacementRange:)`
(undoable) with `isApplyingPairEdit` set, maps tracked positions in
`shouldChangeText(in:replacementString:)` (exact range, fires for typing, paste, undo and the
find bar; NSTextView nests a one-range `shouldChangeText(inRanges:)` inside it, so only calls
with several ranges reset the pairs) and prunes on `setSelectedRanges`. The text storage
delegate is deliberately not used: its `editedRange` is widened by attribute fix-ups (probed
2026-09-07). *Find*: SwiftUI's generated Edit menu has no Find items at all (probed
2026-09-07), so `uncialApp` adds Edit ▸ Find (`CommandGroup(after: .pasteboard)`, five items
from `AppShortcut`) driving focused value `findInDocument` (`FindAction`, with
`supportsReplace`): with an editor pane visible it goes to `EditorHandle.performFind`, which
makes the text view first responder and calls `performTextFinderAction` with the action's tag
(the native bar carries the replace row); in Read Only it goes to `PreviewFindController`
(`@Observable`; `PreviewHandle` holds the `WKWebView`), whose `PreviewFindBar` sits above the
page and uses `WKWebView.find(_:configuration:)` (case-insensitive, wrapping; works with
content JavaScript off) plus `PreviewScripts.countMatches` over `innerText` for the count.
`WKWebView` is not an `NSTextFinderClient` (probed 2026-09-08). Find and Replace… is disabled
without an editor pane. *Status bar* (`AppSettings.showStatusBar`, off by default): `StatusBarView`
sits under the `HSplitView` in `DocumentView` (mode label left, counts right, `.bar` material)
and shows `DocumentViewModel.statistics`, a `DocumentStatistics` (pure, tested: lines = line
breaks + 1 like the gutter; words = runs of letters, digits and marks, one internal `' ’ - _ . , :`
allowed, CJK one per character, so Markdown markers never count; characters = grapheme clusters
including whitespace) computed synchronously at init and then together with the body in
`render()`'s detached task, so it lags typing by the render delay.

**Settings / first run:** `AppSettings` (`appearance` System/Light/Dark → `NSApp.appearance`,
`theme`, `defaultEditorMode`, `syncScrolling`, `showLineNumbers`, `autoPairing`,
`continueLists`, `showStatusBar`, `hasCompletedFirstRun`; UserDefaults keys of the same names, injectable for tests; a legacy `theme` value of system/light/dark migrates to
`appearance`; `publishTheme()` writes the theme for Quick Look, see Sandbox),
`QuickLookExtensionManager` (drives `/usr/bin/pluginkit` through `ShellCommand`; Install =
`-a` + `-e use`, Remove = `-e ignore`), `DefaultAppManager` (`NSWorkspace` behind the
`DefaultAppWorkspace` protocol so tests use a fake; remembers the previous handler, restores it
or TextEdit; retries once because LaunchServices rejects back-to-back changes). `SettingsView`
is a `TabView`: `GeneralSettingsView` (also shown by `WelcomeView`, which
`WelcomeWindowController` presents from `AppDelegate` when the first-run flag is unset),
`EditorSettingsView`, `ShortcutsSettingsView`, `AboutView` (`AppInfo` from Info.plist).
`NSWorkspace.setDefaultApplication` takes 7–8 s; keep the busy state.

**Concurrency model in the app target:** Swift 5 language mode with
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every type is main-actor isolated unless marked
`nonisolated` (`MarkdownDocument`, because `FileDocument` reads off-main; `ShellCommand`;
`UTType.markdown`). Closures handed to the managers' `perform` helpers are `@MainActor`.
`FileWatcher.onChange` is `@MainActor @Sendable` and always delivered on the main actor.

**Project file facts:** Xcode 26 project with file-system-synchronized groups, so new `.swift`
files under `uncial/`, `UncialQuickLook/`, `uncialTests/` need no pbxproj edit (only `Info.plist`
is excluded via membership exceptions). The pbxproj was hand-edited to add the extension target,
the local package, `MACOSX_DEPLOYMENT_TARGET = 14.0`, `PRODUCT_NAME = Uncial` (target name stays
`uncial`, module `Uncial`, so tests use `@testable import Uncial`). The app entry file is
`uncial/uncialApp.swift`; do not rename it to `UncialApp.swift` (the filesystem is
case-insensitive and git tracks the lowercase name). Bundle ids: `com.maksimradaev.uncial` and
`com.maksimradaev.uncial.QuickLook`; UTI `net.daringfireball.markdown` (system-declared),
`CFBundleTypeRole` Editor.

**Sandbox and App Group:** the app is deliberately unsandboxed (relative images next to any
opened document must be readable); the extension is sandboxed via `ENABLE_APP_SANDBOX` /
`ENABLE_USER_SELECTED_FILES` build settings. Both targets have a `.entitlements` file
(`CODE_SIGN_ENTITLEMENTS`) that adds only the App Group `XWTLHG45H7.com.maksimradaev.uncial`
(Team-ID prefix: no provisioning profile, no consent prompt); the build-setting entitlements
merge into it. Hardened Runtime on both. `SharedSettings` writes `settings.plist` (key `theme`)
into `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` from the app (launch
and every change) and the extension reads it; `UserDefaults(suiteName:)` is avoided because an
unsandboxed app does not resolve it to the group container. Probed 2026-09-06: the appex can
read only the previewed file (`Operation not permitted` on siblings and on listing the
directory; home is the container), so Quick Look previews have no images. A
`temporary-exception.files.absolute-path.read-only` entitlement does merge with the
build-setting sandbox, but the owner chose not to ship one.

## Verifying things that have no UI test

- Quick Look: register the built appex (`pluginkit -a …/Uncial.app/Contents/PlugIns/UncialQuickLook.appex`),
  run `qlmanage -p file.md` in the background, and confirm `pgrep -fl UncialQuickLook` shows the
  extension process. `qlmanage -p -o` crashes for extension-based previews and `qlmanage -d` rejects
  its argument; screen capture is not permitted for the terminal.
- Logs: `log` is a zsh builtin here; use `/usr/bin/log show --predicate 'subsystem == "com.maksimradaev.uncial"'`.
  The extension logs under category `quicklook`, the Welcome window under `welcome`. The
  extension's "Rendering preview" line is `.info` level: add `--info` or it will not show.
- An app launched with `open -a` from this terminal never becomes active (no key window, so
  focused-value menu items read as disabled and `osascript … activate` does not help); use
  `open -a` with an absolute path. Check computed CSS in the app with a temporary
  `evaluateJavaScript(getComputedStyle…)` log, not screenshots.
- Preferences: the app is unsandboxed but a stale container exists for its bundle id, so use the
  path form: `defaults read /Users/flame/Library/Preferences/com.maksimradaev.uncial`.
  Reset first run with `defaults delete <that path> hasCompletedFirstRun`.
- Windows without Accessibility: a CGWindowList script lists an app's window titles and sizes.
- To see AppKit chrome (gutter, find bar, controls), a temporary probe can render the window's
  content view offscreen (`bitmapImageRepForCachingDisplay` + `cacheDisplay`, write a PNG into
  the scratchpad) and the file can be viewed; the text view's glyphs and the web view come out
  blank. Typing can be simulated with `insertText(_:replacementRange:)` (`NSNotFound` range),
  `insertNewline(nil)` and `deleteBackward(nil)` on the text view. `NSLog` from the app does not
  reach `log show`; write probe output to a file. The web view's content is captured with
  `WKWebView.takeSnapshot(with:)` (works for a non-key window); a SwiftUI view can be rendered on
  its own through an offscreen `NSHostingView` + `cacheDisplay`.
- Undo groups never close in a terminal-launched app (no events), so anything that depends on
  `NSUndoManagerDidCloseUndoGroup` (NSDocument's change count) must be provoked with
  `endUndoGrouping()` in a probe. Leave at least two seconds between killing one launch and
  starting the next: `open -a` reaches an instance that is still terminating.
- `xcodebuild test` re-signs the Debug app with test-host entitlements; run a plain `build` before
  inspecting entitlements with `codesign -d --entitlements :-`.
- Leave the machine as found after experiments: default Markdown app (currently Xcode),
  first-run flag, and Quick Look election.

## Conventions

- TDD: package logic gets a failing `swift test` first; app logic that touches AppKit goes behind a
  protocol (`DefaultAppWorkspace`) or an injectable `UserDefaults` so `uncialTests` can cover it.
  Pure decisions get their own type (`DiskSync`, `JavaScriptLiteral`, `AppShortcut`, `AppInfo`).
- `FileWatcherTests` and `DocumentViewModelTests` are timing-based (50 ms debounce, 300–900 ms
  settle); keep them generous.
- Commit messages: Conventional Commits, imperative, ≤50-char subject, body only for the why.
- README documents user-facing behavior; specs document decisions. Update both when behavior changes.
