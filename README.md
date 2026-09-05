# Uncial

Uncial is a small native macOS Markdown reader. Open a `.md` file and it renders
GitHub-flavored Markdown right away, follows the system light or dark appearance,
and re-renders whenever the file changes on disk. It ships with a Quick Look
extension, so pressing Space on a Markdown file in Finder shows the rendered
document instead of raw text.

## Features

- GitHub-flavored Markdown through cmark-gfm: tables, task lists, strikethrough,
  autolinks, footnotes, fenced code, raw HTML (dangerous tags are filtered).
- Automatic re-rendering when the file changes, including atomic saves from
  editors such as VS Code, Vim, or TextEdit. Scroll position is kept.
- Light and dark appearance follow macOS without a restart.
- Images referenced by relative path are embedded, so READMEs look like they do
  on GitHub.
- Heading anchors: `[Setup](#setup)` style links work.
- External links open in the default browser. Local `.md` links open in a new
  Uncial window.
- YAML front matter is shown as a small block above the document.
- Quick Look preview (Space in Finder, Quick Look in Spotlight, Mail attachments)
  with the same rendering.
- ⌘R reloads on demand. Pinch to zoom.
- Settings (⌘,) for theme, the Quick Look extension, and the default Markdown app;
  offered once in a Welcome window on first launch.

## Requirements

- macOS 14 Sonoma or later to run.
- Xcode 26 to build.

## Install

```sh
git clone https://github.com/vflame6/uncial.git
cd uncial
make install
```

`make install` builds a Release `Uncial.app`, copies it to `/Applications`,
launches it once so macOS registers the Quick Look extension, and clears the
Quick Look cache.

You can also open `uncial.xcodeproj` in Xcode, pick the `uncial` scheme, and run.

## Enabling the Quick Look extension

1. Select any `.md` file in Finder and press Space. You should see the rendered
   document.
2. If you still see plain text, open System Settings ▸ General ▸
   Login Items & Extensions ▸ Quick Look and enable **Uncial Quick Look**.
   (On macOS 14 the switch lives under Privacy & Security ▸ Extensions ▸ Quick Look.)
3. Reset Quick Look if needed:

   ```sh
   qlmanage -r && qlmanage -r cache
   pluginkit -m -v -p com.apple.quicklook.preview | grep uncial
   ```

Only one Quick Look extension can preview a file type. If another Markdown
previewer is installed (QLMarkdown, Peek, Marked, …), disable it in the same
settings pane or macOS may keep using it.

## Usage

- Right-click a Markdown file ▸ Open With ▸ Uncial, drop it on the Dock icon, or
  run `open -a Uncial README.md`.
- File ▸ Open (⌘O) and Open Recent work as in any document app.
- View ▸ Reload (⌘R) re-reads the file if you ever need to force it.

## Settings

Open Settings with ⌘, (Uncial ▸ Settings…). On the first launch the same controls
appear in a Welcome window with **Skip** and **Done**; either one dismisses it for good.

- **Theme**: System, Light, or Dark. Windows and the rendered document switch
  immediately, no reload needed.
- **Quick Look extension**: *Install* registers the extension bundled in this copy
  of Uncial and enables it. *Remove* disables it, the same switch as System
  Settings ▸ Extensions ▸ Quick Look.
- **Default app**: *Make Default* makes Uncial the handler for Markdown files.
  *Remove* hands the role back to the app that had it before, or TextEdit if that
  is unknown. macOS takes a few seconds to apply either change.

To see the Welcome window again:

```sh
defaults delete com.maksimradaev.uncial hasCompletedFirstRun
```

## How it works

| Part | What it does |
|---|---|
| `Packages/UncialCore` | Swift package. Turns Markdown into a self-contained HTML page: cmark-gfm parsing, heading ids, front matter, image inlining, GitHub-like CSS. Also the file watcher. |
| `uncial` (app target) | SwiftUI document app. Shows the HTML in a `WKWebView` with JavaScript disabled and reloads it when the watcher fires. Settings and the first-run Welcome window drive `pluginkit` and `NSWorkspace` for the two system integrations. |
| `UncialQuickLook` | Quick Look Preview Extension. Returns the same HTML through `QLPreviewReply`, so Finder renders it. |

Design notes live in `docs/superpowers/specs/2026-09-05-uncial-design.md` and the
implementation plan in `docs/superpowers/plans/2026-09-05-uncial-plan.md`.

## Development

```sh
make core-test   # unit tests for the renderer and watcher (swift test)
make test        # core tests + app unit tests via xcodebuild
make build       # Release build into ./build
make icon        # regenerate the app icon PNGs
make clean
```

The Makefile exports `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
so the commands work even when `xcode-select` points at the Command Line Tools.
Override it with `make DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer …`.

## Known limitations

- No syntax highlighting inside code blocks yet.
- No Mermaid diagrams or math.
- The app itself is not sandboxed. That is what lets it read images next to any
  document you open. The Quick Look extension is sandboxed, as macOS requires.
- Links inside a Quick Look preview are not clickable. Open the file in Uncial
  for that.
