# Uncial — macOS Markdown reader with Quick Look preview

Date: 2026-09-05
Status: approved by default (autonomous run; decisions below are recorded as assumptions the owner can reverse)

## Summary

Uncial is a native macOS app that opens Markdown files and shows them rendered
(GitHub-flavored, light/dark aware). Rendering is automatic: a file renders as
soon as it opens and re-renders whenever it changes on disk. A bundled Quick
Look Preview Extension renders the same HTML when the user presses Space on a
Markdown file in Finder.

Three pieces share one rendering pipeline:

| Piece | Type | Role |
|---|---|---|
| `UncialCore` | local Swift package | Markdown → self-contained HTML; file watching |
| `Uncial.app` | SwiftUI document app (target `uncial`) | Reader window with live reload |
| `UncialQuickLook.appex` | Quick Look Preview Extension | Space-bar preview in Finder |

## Goals

- Open `.md`-family files from Finder ("Open With"), the Dock, `open -a`, and File ▸ Open.
- Render GitHub-flavored Markdown: headings, emphasis, lists, task lists, tables,
  fenced code, blockquotes, strikethrough, autolinks, footnotes, raw HTML (tag-filtered).
- Follow system appearance (light/dark) without a restart.
- Re-render automatically when the file changes on disk, keeping scroll position.
- Inline images referenced by relative path next to the document.
- Links: external → default browser; local Markdown → new Uncial window; `#anchors` → scroll.
- Quick Look: Space in Finder shows the rendered document with the same styling.

## Non-goals (v1)

Editing, syntax highlighting of code blocks, Mermaid/LaTeX, zoom, table of
contents sidebar, export/print, Quick Look thumbnails, App Store distribution.
Each is listed under Future work; none blocks v1.

## Decisions and assumptions

1. **Markdown engine: cmark-gfm** via SwiftPM package `swiftlang/swift-cmark`
   (branch `gfm`, products `cmark-gfm` and `cmark-gfm-extensions`). Reason: exact
   GitHub semantics (tables, strikethrough, autolink, tagfilter, tasklist,
   footnotes), C speed, battle-tested. Apple's `swift-markdown` has no HTML
   output; pure-Swift parsers lack GFM parity.
2. **Quick Look = data-based preview.** `QLPreviewProvider` returns a
   `QLPreviewReply` of content type HTML. Quick Look owns the web view. No
   JavaScript is needed or assumed in the preview. Simpler than a view-based
   controller and immune to WKWebView restrictions inside extensions.
3. **App Sandbox: off for the app, on for the extension.** A sandboxed
   document viewer receives access to the opened file only, so relative images
   (`![](docs/shot.png)`) would fail for Finder-opened files. Quick Look
   extensions must be sandboxed and are. Hardened Runtime stays on for both.
   Reversible: set `ENABLE_APP_SANDBOX = YES` and add a folder-access flow.
4. **Deployment target macOS 14.0** (template had 26.5). Every API used exists
   on 14 (`QLPreviewProvider` 12+, `DocumentGroup(viewing:)` 12+,
   `@Observable` 14+, `ContentUnavailableView` 14+).
5. **Bundle IDs** keep the owner's prefix: `com.maksimradaev.uncial` (app) and
   `com.maksimradaev.uncial.QuickLook` (extension). Team `XWTLHG45H7`, automatic
   signing, unchanged.
6. **Product name `Uncial`** (bundle `Uncial.app`, module `Uncial`); the Xcode
   target keeps its name `uncial`. Test targets' `TEST_HOST` and imports follow.
7. **Existing project is extended, not regenerated.** The Xcode 26 project uses
   file-system-synchronized groups, so new source folders need only a group entry
   and a target. SwiftData template files are deleted.
8. **Untrusted content.** Markdown files are treated as untrusted: raw HTML
   passes through cmark's tagfilter (`script`, `iframe`, `style`, … escaped),
   and the app's WKWebView disables content JavaScript. Remote images still
   load (expected for README badges).
9. **Nothing is committed** in this run; the owner reviews and commits.

## Architecture

```
Finder / Dock / File▸Open                      Finder (Space)
        │                                            │
        ▼                                            ▼
 DocumentGroup(viewing:)                    QuickLook host process
        │  MarkdownDocument (FileDocument)           │
        ▼                                            ▼
 DocumentView ─► DocumentViewModel        PreviewProvider (QLPreviewProvider)
        │            │  FileWatcher                  │
        │            ▼                               ▼
        │     UncialCore.MarkdownRenderer  ◄─────────┘
        │            │  renderDocument(markdown, baseURL) → HTML
        ▼            ▼
   WebView (WKWebView, JS off)          QLPreviewReply(dataOfContentType: .html)
```

## Components

### UncialCore (Packages/UncialCore)

Swift package, macOS 14+, Swift 5 language mode, depends on `swift-cmark`.
Tested with `swift test` (Swift Testing). Public API:

```swift
public struct MarkdownRenderer {
    public init()
    /// GFM → HTML fragment. Heading ids added. No CSS, no <html>.
    public func renderBody(_ markdown: String) -> String
    /// Full standalone HTML page: CSS inlined, images under baseURL inlined as data: URIs.
    public func renderDocument(_ markdown: String, title: String, baseURL: URL?) -> String
}

public enum FrontMatter {
    /// Splits a leading YAML block delimited by `---` lines. Returns nil when absent.
    public static func split(_ markdown: String) -> (frontMatter: String?, body: String)
}

public enum HeadingAnchors {
    /// Adds GitHub-style `id` attributes to <h1>–<h6> lacking one. Duplicates get -1, -2, …
    public static func addIDs(to html: String) -> String
}

public struct ImageInliner {
    public init(baseURL: URL, maxBytes: Int = 20 * 1024 * 1024)
    /// Rewrites relative <img src> to data: URIs when the file exists and fits maxBytes.
    public func inline(_ html: String) -> String
}

public enum Stylesheet {
    public static let css: String   // GitHub-like, light/dark via prefers-color-scheme
}

public final class FileWatcher {
    public init(url: URL, debounce: TimeInterval = 0.1, queue: DispatchQueue = .main,
                onChange: @escaping () -> Void)
    public func start()
    public func stop()
}
```

Rendering pipeline (`renderDocument`):

1. `FrontMatter.split` — a leading `---` block is emitted as
   `<pre class="front-matter">` (shown, not interpreted) ahead of the body.
2. cmark-gfm parse with extensions `table`, `strikethrough`, `autolink`,
   `tagfilter`, `tasklist`; options `UNSAFE | FOOTNOTES | VALIDATE_UTF8`.
   `cmark_render_html` with the parser's extension list.
3. `HeadingAnchors.addIDs` — slug = lowercase text, strip tags/punctuation
   (keep letters, digits, spaces, hyphens), spaces → `-`; dedupe with `-n`.
4. `ImageInliner.inline` when `baseURL` is given — relative or `file:` `src`
   values resolved against the document directory, percent-decoded, read, and
   replaced by `data:<mime>;base64,…`. Missing/oversized files keep their `src`.
5. Wrap: `<!doctype html><html><head><meta charset><meta name=viewport>
   <meta name="color-scheme" content="light dark"><title><style>` +
   `<article class="markdown-body">` … `</article>`.

FileWatcher: `DispatchSource.makeFileSystemObjectSource` on the file
descriptor for `.write .extend .attrib .delete .rename .revoke`. On
delete/rename (atomic saves by editors) it closes the descriptor, re-opens the
path with a short retry (up to ~1 s), and re-arms. Events coalesce through a
debounce before `onChange` fires on the given queue.

### Uncial app (folder `uncial/`)

- `UncialApp.swift` — `@main App` with `DocumentGroup(viewing: MarkdownDocument.self)`;
  `.commands` adds View ▸ Reload (⌘R). Window default 900×760, minimum 480×320.
- `MarkdownDocument.swift` — `FileDocument`, `readableContentTypes = [.markdown]`
  (`UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)`).
  Reads text as UTF-8, falls back to lossy decoding.
- `DocumentViewModel.swift` — `@Observable @MainActor`; holds `fileURL`, `html`,
  `error`; owns `FileWatcher`; `reload()` re-reads and re-renders.
- `DocumentView.swift` — SwiftUI view: `WebView(html:baseURL:)` or
  `ContentUnavailableView` on read error. Receives the Reload command via
  a `FocusedValue`.
- `WebView.swift` — `NSViewRepresentable` over `WKWebView`. Configuration:
  `allowsContentJavaScript = false`, `underPageBackgroundColor` = window
  background. On new HTML: read `window.scrollY` via `evaluateJavaScript`
  (native evaluation still works), `loadHTMLString(html, baseURL: docDir)`,
  restore scroll on `didFinish`. `WKNavigationDelegate.decidePolicyFor`:
  - initial load / same-document fragment → allow
  - `file:` URL with Markdown extension → `NSDocumentController.shared.openDocument`
  - anything else user-activated → `NSWorkspace.shared.open`, cancel
- `Info.plist` — `CFBundleDocumentTypes` (Viewer, `LSHandlerRank = Alternate`,
  `net.daringfireball.markdown`), `UTImportedTypeDeclarations` for the same
  UTI with extensions `md markdown mdown mkd mkdn mdwn mdtxt mdtext`.
- Assets: generated app icon (rounded square, "U" glyph) in `AppIcon.appiconset`.

### UncialQuickLook extension (folder `UncialQuickLook/`)

- `PreviewProvider.swift` — `final class PreviewProvider: QLPreviewProvider,
  QLPreviewingController`; `providePreview(for:)` returns
  `QLPreviewReply(dataOfContentType: .html, contentSize: 800×900)` whose data
  block reads the file, calls `renderDocument(markdown, title:, baseURL: fileURL)`,
  sets `stringEncoding = .utf8` and `title`.
- `Info.plist` — `NSExtension` with `NSExtensionPointIdentifier =
  com.apple.quicklook.preview`, `NSExtensionPrincipalClass =
  $(PRODUCT_MODULE_NAME).PreviewProvider`, attributes `QLIsDataBasedPreview =
  YES`, `QLSupportedContentTypes = [net.daringfireball.markdown]`,
  `QLSupportsSearchableItems = NO`.
- Entitlements come from build settings, the same way the app target already
  works: `ENABLE_APP_SANDBOX = YES` and `ENABLE_USER_SELECTED_FILES = readonly`
  generate `com.apple.security.app-sandbox` and
  `com.apple.security.files.user-selected.read-only`. No `.entitlements` file.
- Build settings: bundle id `com.maksimradaev.uncial.QuickLook`, `SKIP_INSTALL = YES`,
  embedded into `Uncial.app/Contents/PlugIns` by the app target.

## Project changes

- `uncial.xcodeproj/project.pbxproj`: add native target `UncialQuickLook`
  (`com.apple.product-type.app-extension`) with its own synchronized root group,
  Sources/Frameworks/Resources phases and Debug/Release configurations; add
  local package reference `Packages/UncialCore` and product dependency
  `UncialCore` to both `uncial` and `UncialQuickLook`; add an "Embed Foundation
  Extensions" copy-files phase (`dstSubfolderSpec = 13`) to the app; set
  `MACOSX_DEPLOYMENT_TARGET = 14.0`, app `ENABLE_APP_SANDBOX = NO`,
  `ENABLE_USER_SELECTED_FILES = readonly`, `PRODUCT_NAME = Uncial`,
  `INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.productivity`.
- Delete `uncial/Item.swift`, `uncial/ContentView.swift`; replace `uncialApp.swift`.
- `uncialTests`/`uncialUITests`: update to `@testable import Uncial`; keep one
  smoke test each.
- `Makefile`: `build`, `test`, `install` (copies `Uncial.app` to `/Applications`,
  runs `qlmanage -r`), `clean`. All `xcodebuild` calls use
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` so they work while
  `xcode-select` points at Command Line Tools.
- `README.md`: features, install, enabling the Quick Look extension
  (System Settings ▸ General ▸ Login Items & Extensions ▸ Quick Look), troubleshooting
  (`qlmanage -r`, `pluginkit -m -p com.apple.quicklook.preview`).
- `.gitignore`: Xcode/SwiftPM build products and `xcuserdata`.

## Error handling

| Situation | Behavior |
|---|---|
| File unreadable / not UTF-8 | UTF-8 first, then lossy decode; if the read itself fails, window shows `ContentUnavailableView` with the error |
| Relative image missing or > 20 MB | `src` left untouched (broken image / alt text) |
| File deleted or moved while open | Last render stays; watcher retries re-open ~1 s, then stops until Reload |
| Quick Look read/render failure | `providePreview` throws; Quick Look falls back to its default text preview |
| cmark returns NULL | Renderer returns an empty body; never crashes |

## Security

- Markdown is untrusted input. cmark `tagfilter` escapes dangerous raw tags;
  the app disables content JavaScript so `onclick`/`javascript:` cannot run.
- WKWebView base URL is the document's directory so relative links resolve;
  file-URL cross-origin reads are off (WebKit default) and scripts are off.
- Quick Look renders HTML with system defaults (no script execution).
- Extension is sandboxed; app runs with Hardened Runtime and no extra entitlements.

## Testing

- **UncialCore (`swift test`)**: headings/tables/task lists/strikethrough/
  autolinks/footnotes render; raw `<script>` is escaped; heading ids and
  duplicate suffixes; front-matter split; image inlining (present, missing,
  oversized, absolute-URL untouched); full document has CSS and `color-scheme`;
  FileWatcher fires on in-place write and on atomic replace (temp + rename), and
  coalesces bursts.
- **App**: `xcodebuild build` for `uncial` (Debug) succeeds with no warnings in
  new code; smoke run `open -a Uncial README.md`; edit the file and observe
  re-render; `Uncial.app/Contents/PlugIns/UncialQuickLook.appex` present.
- **Quick Look**: after install, `pluginkit -m -p com.apple.quicklook.preview`
  lists `com.maksimradaev.uncial.QuickLook`; `qlmanage -p README.md` opens a
  rendered preview without errors in its log.
- **Visual**: render the sample document to HTML and inspect in a browser
  (light and dark) before wiring into the app.

## Future work

Syntax highlighting (highlight.js via JavaScriptCore, works in the extension
too), Mermaid, zoom (⌘+/−), outline sidebar, print/PDF export, Quick Look
thumbnails, sandboxed build with folder-access bookmarks for App Store.
