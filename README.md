# Uncial

Uncial is a small native macOS Markdown reader and editor. Open a `.md` file and
it renders GitHub-flavored Markdown right away, follows the system light or dark
appearance, and re-renders whenever the file changes on disk. Switch to Live
Preview to edit with the Markdown rendered in place, or to Split View to edit
the source next to the rendered page; changes are written back to the file as
you type. It ships with Quick Look extensions, so pressing Space on a Markdown
file in Finder shows the rendered document instead of raw text, and Finder icons,
Open panels and Get Info show a thumbnail of the rendered page.

## Features

- GitHub-flavored Markdown through cmark-gfm: tables, task lists, strikethrough,
  autolinks, footnotes, fenced code, raw HTML (dangerous tags are filtered),
  and LaTeX math (`$…$`, `$$…$$`, ```` ```math ```` fences) rendered to MathML
  with KaTeX at render time, so no script runs in the page.
- Mermaid diagrams: flowcharts, sequence, state, class and ER diagrams and XY
  charts in ```` ```mermaid ```` fences become inline SVG in the theme's colors
  (beautiful-mermaid at render time, again without page scripts). Other Mermaid
  types stay code blocks.
- Automatic re-rendering when the file changes, including atomic saves from
  editors such as VS Code, Vim, or TextEdit. Scroll position is kept.
- Four editor modes per window: **Read Only**, **Live Preview** (Markdown
  rendered in place, the line with the cursor shows its source), **Split View**
  (source beside the rendered page, updating as you type) and **Raw Editor**.
  Edits are saved to the file automatically half a second after you stop typing.
- Three document themes, each with light and dark variants: **macOS** (system
  fonts and colors, looks like a native document), **GitHub**, and **Solarized**.
  The editor's colors follow the theme, and so do Quick Look previews.
- The source editor colors Markdown: headings, emphasis, code, links, list
  markers, quotes, rules and front matter. In Split View the two panes scroll
  together.
- Editor conveniences: optional line numbers (also as source lines in the
  rendered page), brackets and Markdown markers that close themselves as you
  type, lists and quotes that continue on Return, and Edit ▸ Find with find
  and replace.
- An optional status bar with the current mode and the document's line, word
  and character counts.
- Light and dark appearance follow macOS without a restart, or can be forced.
- Images referenced by relative or absolute path are embedded, so READMEs look
  like they do on GitHub. Remote images load in the app.
- Heading anchors: `[Setup](#setup)` style links work.
- External links open in the default browser. Local `.md` links open in a new
  Uncial window.
- YAML front matter is shown as a small block above the document.
- Quick Look preview (Space in Finder, Quick Look in Spotlight, Mail attachments)
  with the same rendering, and Quick Look thumbnails: Finder icons, the Open
  panel's preview column and Get Info show the page's headings, text, lists,
  quotes, code and tables instead of a plain-text icon.
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
launches it once so macOS registers the Quick Look extensions, and clears the
Quick Look cache.

You can also open `uncial.xcodeproj` in Xcode, pick the `uncial` scheme, and run.

## Enabling the Quick Look extensions

1. Select any `.md` file in Finder and press Space. You should see the rendered
   document, and the file's icon should show a small page of it.
2. If you still see plain text, open System Settings ▸ General ▸
   Login Items & Extensions ▸ Quick Look and enable **Uncial Quick Look** (previews)
   and **Uncial Thumbnails** (icons and Open panels).
   (On macOS 14 the switches live under Privacy & Security ▸ Extensions ▸ Quick Look.)
3. Reset Quick Look if needed; the cache reset also throws away old thumbnails:

   ```sh
   qlmanage -r && qlmanage -r cache
   pluginkit -m -v -p com.apple.quicklook.preview | grep uncial
   pluginkit -m -v -p com.apple.quicklook.thumbnail | grep uncial
   ```

Only one Quick Look extension can preview a file type, and one can draw its
thumbnails. If another Markdown previewer is installed (QLMarkdown, Peek,
Marked, …), disable it in the same settings pane or macOS may keep using it.

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
| Live Preview | One editor with the Markdown rendered in place; the line with the cursor shows its source | ⌥⌘2 |
| Split View | Markdown source on the left, rendered document on the right | ⌥⌘3 |
| Raw Editor | Markdown source only | ⌥⌘4 |

⇧⌘E cycles through the four. New windows start in the mode chosen in
Settings ▸ Editor (Split View by default).

The file on disk is the source of truth. Whatever you type is written to it
half a second after you pause, when you leave an editing mode, when the window
closes, and on quit; ⌘S writes immediately. If another program changes the file
while you are not editing, the editor and the preview pick up the new contents;
if it happens while you have unsaved keystrokes, yours win. The editor uses
SF Mono, wraps long lines, keeps smart quotes and dashes off (they break
Markdown), and has undo. Markdown syntax is
colored in place: headings and links in the theme's accent, code in its code
color, quotes, rules, URLs, front matter, table pipes and HTML tags muted. Emphasis is italic, strong
text bold; the font size never changes, so nothing jumps while you type.

**Live Preview.** The same editor, but Markdown is rendered where it stands, the
way Obsidian does it: headings grow (SF Mono bold, 22 pt for `#` down to 13 pt
for `######`), `**bold**`, `*emphasis*` and `~~struck~~` text are styled with
their markers hidden, `` `code` `` sits on a tint, links show their text in the
accent color (⌘-click opens them; a plain click just places the cursor), bullets
become •, wrapped list lines hang under their text, quotes are indented behind
a bar, fenced code blocks get a rounded background with the fence lines
hidden (only an info string such as `swift` stays), rules draw as a line and
front matter is muted. The line with the cursor, or the whole fenced block the
cursor is in, shows its markers in the muted color; a selection reveals every
line it touches, and a find match reveals its line. Typing happens on that
revealed line, so auto-pairing, list continuation, undo, find and replace and
line numbers behave exactly as in Raw Editor, and copying gives Markdown.
Task items show a check box in place of `[ ]`; click it to toggle the item
(undoable, saved like typing). A local image referenced as `![alt](path)`
appears under its line, scaled to fit the column, with the alt text above it.
With Settings ▸ Editor ▸ Live Preview ▸ *Limit line width to a readable
column* (on by default) the text sits in a centered column of up to 720
points, like the rendered page. Tables stay text but line up: every column is
padded to its widest cell (right- and center-aligned columns follow the
delimiter row), the header row is bold, the outer pipes hide and the delimiter
row draws as a rule. Setext headings (`Title` over `===` or `---`) render like
`#` headings with the underline drawn as a rule, footnote references show as
small raised labels, reference-style links resolve through their definitions,
escape backslashes hide, and HTML renders as far as a text view can: tags hide,
`<b>`, `<i>`, `<u>`, `<s>`, `<code>`, `<kbd>`, `<mark>`, `<sup>`, `<sub>`, `<a>`
and `<h1>`–`<h6>` style their text, an `align` attribute or `<center>` aligns
the paragraph, `<img>` draws like a Markdown image and comments vanish. Remote
images load in the background and appear once fetched. Math keeps its TeX in
the code color with the dollars hidden; `$$` blocks sit on the code tint. Front
matter and link definitions stay as source.

In Split View the panes follow each other: scroll the source and the
rendered page moves to the same block, scroll the page and the source follows.
Switch it off in Settings ▸ Editor if you prefer independent scrolling.

**Line numbers.** Settings ▸ Editor ▸ *Show line numbers* adds a gutter with
one number per line of the file; wrapped continuation rows stay unnumbered,
and the number of the line with the cursor is highlighted. The rendered page
gets the same numbers: each heading, paragraph, list item or quote is labeled
with the source line it starts on, and code blocks number every line, so a
Read Only window can still point at "line 42" and Split View's two panes
carry matching numbers.

**Auto-pairing.** Typing `(`, `[`, `{`, `` ` ``, `*`, `_` or `"` inserts the
matching closer after the cursor; typing that closer again skips over it, and
Backspace inside an empty pair removes both characters. `*`, `_` and `` ` ``
grow into runs: type `*` twice for `**|**`, three backticks for
```` ```|``` ````, then press Return to get a fenced code block (an info string
such as ```` ```swift ```` typed before Return is kept). A space or Return
right after a lone `*` or `_` drops the closer, so `* item` and `***` keep
working. `~` pairs only at the start of a line, where it can open `~~text~~`
or a `~~~` fence (three tildes plus Return), so `~5 min` stays as typed. With
text selected, any of those characters (and `<`, `'`) wraps the selection
instead; press `*` twice to make it bold. Pairs are only inserted in front of
whitespace, punctuation or another closer, and `*`/`_` never inside a word
(`snake_case` stays as typed). Switch it off in Settings ▸ Editor.

**Lists and quotes.** Return inside a list item starts the next one: `- `,
`* ` and `+ ` repeat, numbered items count up (`1.` → `2.`, `1)` → `2)`),
task items get an empty box, quotes keep their `> ` prefix (nested ones too),
indentation and spacing are kept, and any text after the cursor moves to the
new item. Return on an empty item removes its marker, so pressing Return twice
ends the list. Switch it off in Settings ▸ Editor.

**Status bar.** Settings ▸ Editor ▸ *Show status bar* adds a footer to every
window: the current mode on the left, the document's line, word and character
counts on the right, updating as you type. Lines are counted as the gutter
numbers them (an empty document has one). Words are runs of letters and
digits, so Markdown markers such as `#`, `*` and `-` are not counted;
`don't`, `well-known`, `3,857` and `e.g.` are one word each, and every
Chinese, Japanese or Korean character counts as a word. Characters are
counted as a person would, spaces and line breaks included.

**Find and replace.** Edit ▸ Find (⌘F) opens the find bar above the source;
Edit ▸ Find and Replace… (⌥⌘F) adds the replace field with Replace, All and
Replace & Find. ⌘G and ⇧⌘G step through matches, ⌘E searches for the
selection, Esc closes the bar. In Read Only mode ⌘F opens a find bar above
the rendered page instead: matches are selected and scrolled into view with a
count of how many there are. Replacing needs the source, so Find and Replace…
is available in every mode but Read Only.

## Settings

Open Settings with ⌘, (Uncial ▸ Settings…). On the first launch the General
controls appear in a Welcome window with **Skip** and **Done**; either one
dismisses it for good. The Welcome window and the Open panel both open in the
middle of the screen.

**General**

- **Appearance**: System, Light, or Dark. Windows, the editor and the rendered
  document switch immediately, no reload needed.
- **Theme**: macOS, GitHub, or Solarized. Each has a light and a dark variant that
  follows the appearance. Open documents restyle in place; Quick Look previews
  use the same theme (they always follow the system appearance).
- **Quick Look**: *Install* registers the preview and thumbnail extensions bundled
  in this copy of Uncial and enables them. *Remove* disables them, the same
  switches as System Settings ▸ Extensions ▸ Quick Look.
- **Default app**: *Make Default* makes Uncial the handler for Markdown files.
  *Remove* hands the role back to the app that had it before, or TextEdit if that
  is unknown. macOS takes a few seconds to apply either change.

**Editor**: the mode new windows start in (Read Only, Live Preview, Split View,
Raw Editor), the status bar, the text size (System, or Custom with a stepper;
View ▸ Zoom In ⌘=, Zoom Out ⌘- and Actual Size ⌘0 change it too, and the editor
and the rendered page scale together), line numbers, automatic closing of brackets, quotes
and Markdown markers, list and quote continuation on Return, the readable
column in Live Preview, whether Split View keeps the source and the rendered
page scrolled to the same place, and how Split View divides its width between
source and preview: half each unless you change it. Entering Split View applies
the setting; dragging the divider changes that window until it leaves Split
View.

**Shortcuts**: a reference list of every keyboard shortcut.

**About**: version, what renders the Markdown, and a link to this repository.

To see the Welcome window again:

```sh
defaults delete com.maksimradaev.uncial hasCompletedFirstRun
```

## How it works

| Part | What it does |
|---|---|
| `Packages/UncialCore` | Swift package. Turns Markdown into a self-contained HTML page: cmark-gfm parsing, heading ids, front matter, math (KaTeX) and diagrams (beautiful-mermaid) rendered through JavaScriptCore at render time, image inlining, and the three themes as CSS. Also the file watcher and the block outline the thumbnails draw. |
| `uncial` (app target) | SwiftUI document app. Shows the HTML in a `WKWebView` with page JavaScript disabled and swaps the rendered body in place as you type. An `NSTextView` provides the editor; the view model writes edits through to the file and reconciles changes that arrive from other programs. Settings and the first-run Welcome window drive `pluginkit` and `NSWorkspace` for the two system integrations. |
| `UncialQuickLook` | Quick Look Preview Extension. Returns the same HTML through `QLPreviewReply`, so Finder renders it. Reads the theme from the App Group container the app writes to. |
| `UncialThumbnail` | Quick Look Thumbnail Extension. Draws the document's outline (headings, text, lists, quotes, code, rules, tables) as a small page with AppKit for Finder icons, Open panels and Get Info, in the theme's light colors. |

## Development

```sh
make core-test   # unit tests for the renderer and watcher (swift test)
make test        # core tests + app unit tests via xcodebuild
make build       # Release build into ./build
make icon        # regenerate the app icon PNGs
make clean
```

`static/demo.md` exercises every rendering and editing feature with an *Expect* note
per section; open it in each mode to check a change by eye.

The Makefile exports `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
so the commands work even when `xcode-select` points at the Command Line Tools.
Override it with `make DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer …`.

## Known limitations

- No syntax highlighting inside code blocks (the editor colors the Markdown
  itself, not the languages inside fences).
- Live Preview renders inline Markdown, task boxes, local images, lists,
  quotes, rules, fenced code, tables (as aligned text), setext headings,
  footnote marks, reference-style links and common HTML (tags hidden, inline
  tags styled, `align` honored on the tag's own line); HTML tables and lists,
  front matter and link definitions stay as source, and math shows as TeX.
- Mermaid: flowcharts, sequence, state, class and ER diagrams and XY charts
  render; pie, gantt, mindmap, timeline and the other types stay code blocks,
  and so does a diagram the renderer cannot parse. Live Preview shows every
  fence as code.
- Thumbnails show the page's text and structure only: no images, math or
  diagrams, and always the light variant of the theme.
- The app itself is not sandboxed. That is what lets it read images next to any
  document you open. The Quick Look extensions are sandboxed, as macOS requires,
  and the sandbox only lets them read the previewed file: images do not appear in
  Quick Look previews or thumbnails.
- Links inside a Quick Look preview are not clickable. Open the file in Uncial
  for that.
- Files stored as UTF-16 or with a byte-order mark are rewritten as plain UTF-8
  the first time you edit them.
