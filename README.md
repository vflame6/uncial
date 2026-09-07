# Uncial

Uncial is a small native macOS Markdown reader and editor. Open a `.md` file and
it renders GitHub-flavored Markdown right away, follows the system light or dark
appearance, and re-renders whenever the file changes on disk. Switch to Live
Preview to edit the source next to the rendered page; changes are written back
to the file as you type. It ships with a Quick Look extension, so pressing Space
on a Markdown file in Finder shows the rendered document instead of raw text.

## Features

- GitHub-flavored Markdown through cmark-gfm: tables, task lists, strikethrough,
  autolinks, footnotes, fenced code, raw HTML (dangerous tags are filtered).
- Automatic re-rendering when the file changes, including atomic saves from
  editors such as VS Code, Vim, or TextEdit. Scroll position is kept.
- Three editor modes per window: **Read Only**, **Live Preview** (source beside
  the rendered page, updating as you type) and **Raw Editor**. Edits are saved
  to the file automatically half a second after you stop typing.
- Three document themes, each with light and dark variants: **macOS** (system
  fonts and colors, looks like a native document), **GitHub**, and **Solarized**.
  The editor's colors follow the theme, and so do Quick Look previews.
- The source editor colors Markdown: headings, emphasis, code, links, list
  markers, quotes, rules and front matter. In Live Preview the two panes scroll
  together.
- Editor conveniences: optional line numbers, brackets and Markdown markers
  that close themselves as you type, and Edit ▸ Find with find and replace.
- Light and dark appearance follow macOS without a restart, or can be forced.
- Images referenced by relative or absolute path are embedded, so READMEs look
  like they do on GitHub. Remote images load in the app.
- Heading anchors: `[Setup](#setup)` style links work.
- External links open in the default browser. Local `.md` links open in a new
  Uncial window.
- YAML front matter is shown as a small block above the document.
- Quick Look preview (Space in Finder, Quick Look in Spotlight, Mail attachments)
  with the same rendering.
- ⌘R reloads on demand. Pinch to zoom.
- Settings (⌘,) with General, Editor, Shortcuts and About tabs; the General
  controls are offered once in a Welcome window on first launch.

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
- File ▸ Open (⌘O) and Open Recent work as in any document app. File ▸ New… (⌘N)
  asks where to create an empty Markdown file and opens it.
- View ▸ Reload (⌘R) re-reads the file if you ever need to force it.

### Editing

Every document window has a mode, chosen with the segmented control in the
toolbar, the View menu, or the keyboard:

| Mode | Shows | Shortcut |
|---|---|---|
| Read Only | The rendered document | ⌥⌘1 |
| Live Preview | Markdown source on the left, rendered document on the right | ⌥⌘2 |
| Raw Editor | Markdown source only | ⌥⌘3 |

⇧⌘E cycles through the three. New windows start in the mode chosen in
Settings ▸ Editor (Live Preview by default).

The file on disk is the source of truth. Whatever you type is written to it
half a second after you pause, when you leave an editing mode, when the window
closes, and on quit; ⌘S writes immediately. If another program changes the file
while you are not editing, the editor and the preview pick up the new contents;
if it happens while you have unsaved keystrokes, yours win. The editor uses
SF Mono, wraps long lines, keeps smart quotes and dashes off (they break
Markdown), and has undo. Markdown syntax is
colored in place: headings and links in the theme's accent, code in its code
color, quotes, rules, URLs and front matter muted. Emphasis is italic, strong
text bold; the font size never changes, so nothing jumps while you type.

In Live Preview the panes follow each other: scroll the source and the
rendered page moves to the same block, scroll the page and the source follows.
Switch it off in Settings ▸ Editor if you prefer independent scrolling.

**Line numbers.** Settings ▸ Editor ▸ *Show line numbers* adds a gutter with
one number per line of the file; wrapped continuation rows stay unnumbered,
and the number of the line with the cursor is highlighted.

**Auto-pairing.** Typing `(`, `[`, `{`, `` ` ``, `*`, `_` or `"` inserts the
matching closer after the cursor; typing that closer again skips over it, and
Backspace inside an empty pair removes both characters. `*`, `_` and `` ` ``
grow into runs: type `*` twice for `**|**`, three backticks for
```` ```|``` ````, then press Return to get a fenced code block (an info string
such as ```` ```swift ```` typed before Return is kept). A space or Return
right after a lone `*` or `_` drops the closer, so `* item` and `***` keep
working. With text selected, any of those characters (and `<`, `~`, `'`) wraps
the selection instead; press `*` twice to make it bold. Pairs are only
inserted in front of whitespace, punctuation or another closer, and `*`/`_`
never inside a word (`snake_case` stays as typed). Switch it off in
Settings ▸ Editor.

**Find and replace.** Edit ▸ Find (⌘F) opens the find bar above the source;
Edit ▸ Find and Replace… (⌥⌘F) adds the replace field with Replace, All and
Replace & Find. ⌘G and ⇧⌘G step through matches, ⌘E searches for the
selection, Esc closes the bar. Find works on the Markdown source, so a
Read Only window has to switch to Live Preview or Raw Editor first.

## Settings

Open Settings with ⌘, (Uncial ▸ Settings…). On the first launch the General
controls appear in a Welcome window with **Skip** and **Done**; either one
dismisses it for good.

**General**

- **Appearance**: System, Light, or Dark. Windows, the editor and the rendered
  document switch immediately, no reload needed.
- **Theme**: macOS, GitHub, or Solarized. Each has a light and a dark variant that
  follows the appearance. Open documents restyle in place; Quick Look previews
  use the same theme (they always follow the system appearance).
- **Quick Look extension**: *Install* registers the extension bundled in this copy
  of Uncial and enables it. *Remove* disables it, the same switch as System
  Settings ▸ Extensions ▸ Quick Look.
- **Default app**: *Make Default* makes Uncial the handler for Markdown files.
  *Remove* hands the role back to the app that had it before, or TextEdit if that
  is unknown. macOS takes a few seconds to apply either change.

**Editor**: the mode new windows start in (Read Only, Live Preview, Raw Editor),
line numbers, automatic closing of brackets, quotes and Markdown markers, and
whether Live Preview keeps the source and the rendered page scrolled to the
same place.

**Shortcuts**: a reference list of every keyboard shortcut.

**About**: version, what renders the Markdown, and a link to this repository.

To see the Welcome window again:

```sh
defaults delete com.maksimradaev.uncial hasCompletedFirstRun
```

## How it works

| Part | What it does |
|---|---|
| `Packages/UncialCore` | Swift package. Turns Markdown into a self-contained HTML page: cmark-gfm parsing, heading ids, front matter, image inlining, and the three themes as CSS. Also the file watcher. |
| `uncial` (app target) | SwiftUI document app. Shows the HTML in a `WKWebView` with page JavaScript disabled and swaps the rendered body in place as you type. An `NSTextView` provides the editor; the view model writes edits through to the file and reconciles changes that arrive from other programs. Settings and the first-run Welcome window drive `pluginkit` and `NSWorkspace` for the two system integrations. |
| `UncialQuickLook` | Quick Look Preview Extension. Returns the same HTML through `QLPreviewReply`, so Finder renders it. Reads the theme from the App Group container the app writes to. |

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

- No syntax highlighting inside code blocks (the editor colors the Markdown
  itself, not the languages inside fences).
- No Mermaid diagrams or math.
- The app itself is not sandboxed. That is what lets it read images next to any
  document you open. The Quick Look extension is sandboxed, as macOS requires,
  and the sandbox only lets it read the previewed file: images do not appear in
  Quick Look previews.
- Links inside a Quick Look preview are not clickable. Open the file in Uncial
  for that.
- Files stored as UTF-16 or with a byte-order mark are rewritten as plain UTF-8
  the first time you edit them.
