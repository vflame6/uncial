# Uncial Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a macOS Markdown reader (`Uncial.app`) that renders GitHub-flavored Markdown, re-renders on file change, and bundles a Quick Look Preview Extension so Space in Finder shows the rendered document.

**Architecture:** One local Swift package (`UncialCore`) turns Markdown into a self-contained HTML page (cmark-gfm + post-processing + inlined CSS) and watches files for changes. The SwiftUI document app shows that HTML in a `WKWebView` and reloads on change. The Quick Look extension returns the same HTML through `QLPreviewReply`. The existing Xcode 26 project is extended in place (new extension target, local package link, setting changes).

**Tech Stack:** Swift 6.3 toolchain from Xcode 26.6, SwiftUI `DocumentGroup(viewing:)`, WebKit, QuickLookUI (`QLPreviewProvider`), SwiftPM with `swiftlang/swift-cmark` (branch `gfm`), Swift Testing.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-05-uncial-design.md`.
- Every `swift`/`xcodebuild` command runs with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the machine's `xcode-select` points at Command Line Tools, which lack `Testing` and `xcodebuild`). Never run `xcode-select -s`.
- Deployment target `14.0` for all targets. Package platform `.macOS(.v14)`.
- Bundle ids: app `com.maksimradaev.uncial`, extension `com.maksimradaev.uncial.QuickLook`. Team `XWTLHG45H7`, `CODE_SIGN_STYLE = Automatic`.
- App target name stays `uncial`; `PRODUCT_NAME = Uncial`. Extension target `UncialQuickLook`.
- App: `ENABLE_APP_SANDBOX = NO`, `ENABLE_HARDENED_RUNTIME = YES`. Extension: `ENABLE_APP_SANDBOX = YES`, `ENABLE_USER_SELECTED_FILES = readonly`.
- Markdown UTI: `net.daringfireball.markdown` (system-declared, conforms to `public.plain-text`).
- cmark options: `CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_VALIDATE_UTF8`; extensions `table strikethrough autolink tagfilter tasklist`.
- Do not commit; leave the working tree for the owner to review (harness rule).
- Do not install into `/Applications`; verify from the build directory and unregister the extension afterwards.
- Temporary files go in the session scratchpad, never `/tmp`.

---

## File map

| Path | Responsibility |
|---|---|
| `Packages/UncialCore/Package.swift` | Package manifest, swift-cmark dependency |
| `Packages/UncialCore/Sources/UncialCore/GFMRenderer.swift` | cmark-gfm C API wrapper → HTML fragment |
| `Packages/UncialCore/Sources/UncialCore/HTMLFixups.swift` | Repairs cmark's broken footnote back-reference markup |
| `Packages/UncialCore/Sources/UncialCore/HTMLEscaping.swift` | Escape / unescape helpers |
| `Packages/UncialCore/Sources/UncialCore/FrontMatter.swift` | Split and render YAML front matter |
| `Packages/UncialCore/Sources/UncialCore/HeadingAnchors.swift` | GitHub-style heading ids |
| `Packages/UncialCore/Sources/UncialCore/ImageInliner.swift` | Relative `<img src>` → data URI |
| `Packages/UncialCore/Sources/UncialCore/Stylesheet.swift` | CSS (light/dark) |
| `Packages/UncialCore/Sources/UncialCore/HTMLDocument.swift` | Wrap body in a full page |
| `Packages/UncialCore/Sources/UncialCore/MarkdownRenderer.swift` | Public pipeline entry point |
| `Packages/UncialCore/Sources/UncialCore/MarkdownText.swift` | Bytes → String decoding |
| `Packages/UncialCore/Sources/UncialCore/FileWatcher.swift` | Change notifications for one file |
| `Packages/UncialCore/Tests/UncialCoreTests/*.swift` | Swift Testing suites |
| `uncial/UncialApp.swift` | `@main`, `DocumentGroup(viewing:)`, Reload command |
| `uncial/ReloadAction.swift` | `FocusedValues.reloadDocument` |
| `uncial/MarkdownDocument.swift` | `FileDocument` + `UTType.markdown` |
| `uncial/DocumentViewModel.swift` | Read, render, watch |
| `uncial/DocumentView.swift` | Web view or error view |
| `uncial/WebView.swift` | `WKWebView` wrapper, scroll restore, link policy |
| `uncial/LinkOpener.swift` | Open links externally / Markdown in Uncial |
| `uncial/Info.plist` | Document types + imported UTI |
| `UncialQuickLook/PreviewProvider.swift` | `QLPreviewProvider` returning HTML |
| `UncialQuickLook/Info.plist` | `NSExtension` declaration |
| `uncial.xcodeproj/project.pbxproj` | Extension target, package link, settings |
| `scripts/make-icon.swift` | Generates `AppIcon.appiconset` PNGs |
| `Makefile`, `README.md`, `.gitignore` | Build/install/docs |

---

### Task 1: Package scaffold and cmark-gfm rendering

**Files:**
- Create: `Packages/UncialCore/Package.swift`
- Create: `Packages/UncialCore/Sources/UncialCore/GFMRenderer.swift`
- Create: `Packages/UncialCore/Sources/UncialCore/MarkdownRenderer.swift` (minimal, grows in Task 6)
- Test: `Packages/UncialCore/Tests/UncialCoreTests/MarkdownRendererTests.swift`

**Interfaces:**
- Produces: `MarkdownRenderer.renderBody(_ markdown: String) -> String`; internal `GFMRenderer.render(_:) -> String`.

- [ ] **Step 1: Write the manifest**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UncialCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UncialCore", targets: ["UncialCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark.git", branch: "gfm"),
    ],
    targets: [
        .target(
            name: "UncialCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ]
        ),
        .testTarget(
            name: "UncialCoreTests",
            dependencies: ["UncialCore"]
        ),
    ]
)
```

- [ ] **Step 2: Write the failing test**

```swift
import Testing
@testable import UncialCore

@Suite struct MarkdownRendererTests {
    let renderer = MarkdownRenderer()

    @Test func rendersGitHubExtensions() {
        let markdown = """
        | a | b |
        |---|---|
        | 1 | 2 |

        - [x] done
        - [ ] todo

        ~~gone~~ see www.example.com
        """
        let html = renderer.renderBody(markdown)
        #expect(html.contains("<table>"))
        #expect(html.contains("<input type=\"checkbox\" checked=\"\" disabled=\"\" />"))
        #expect(html.contains("<del>gone</del>"))
        #expect(html.contains("<a href=\"http://www.example.com\">www.example.com</a>"))
    }

    @Test func filtersDangerousRawHTMLButKeepsSafeHTML() {
        let html = renderer.renderBody("<script>alert(1)</script>\n\n<details><summary>More</summary>Body</details>")
        #expect(html.contains("&lt;script>"))
        #expect(!html.contains("<script>"))
        #expect(html.contains("<details><summary>More</summary>Body</details>"))
    }

    @Test func emptyInputProducesEmptyBody() {
        #expect(renderer.renderBody("") == "")
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd Packages/UncialCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: compile error, `MarkdownRenderer` not found.

- [ ] **Step 4: Implement**

`GFMRenderer.swift`:

```swift
import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Thin wrapper over cmark-gfm: Markdown → HTML fragment with GitHub extensions.
enum GFMRenderer {
    static let extensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]
    static let options: Int32 = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_VALIDATE_UTF8

    private static let registerExtensions: Void = {
        cmark_gfm_core_extensions_ensure_registered()
    }()

    static func render(_ markdown: String) -> String {
        _ = registerExtensions
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        for name in extensionNames {
            if let syntaxExtension = cmark_find_syntax_extension(name) {
                _ = cmark_parser_attach_syntax_extension(parser, syntaxExtension)
            }
        }

        let cString = markdown.utf8CString
        cString.withUnsafeBufferPointer { buffer in
            cmark_parser_feed(parser, buffer.baseAddress, buffer.count - 1)
        }

        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }

        guard let output = cmark_render_html(document, options, cmark_parser_get_syntax_extensions(parser)) else {
            return ""
        }
        defer { free(output) }
        return String(cString: output)
    }
}
```

`MarkdownRenderer.swift` (first version):

```swift
import Foundation

public struct MarkdownRenderer: Sendable {
    public init() {}

    /// GitHub-flavored Markdown → HTML fragment.
    public func renderBody(_ markdown: String) -> String {
        GFMRenderer.render(markdown)
    }
}
```

- [ ] **Step 5: Run tests**

Run: `cd Packages/UncialCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: 3 tests pass. First run clones swift-cmark (needs network).

---

### Task 2: HTML helpers and footnote back-reference repair

**Files:**
- Create: `Packages/UncialCore/Sources/UncialCore/HTMLEscaping.swift`
- Create: `Packages/UncialCore/Sources/UncialCore/HTMLFixups.swift`
- Modify: `Packages/UncialCore/Sources/UncialCore/MarkdownRenderer.swift`
- Test: `Packages/UncialCore/Tests/UncialCoreTests/HTMLEscapingTests.swift`, add a test to `MarkdownRendererTests.swift`

**Interfaces:**
- Produces: `HTMLEscaping.escape(_:) -> String`, `HTMLEscaping.unescape(_:) -> String`, `HTMLFixups.repairFootnoteBackrefs(in:) -> String`.

- [ ] **Step 1: Failing tests**

```swift
import Testing
@testable import UncialCore

@Suite struct HTMLEscapingTests {
    @Test func escapesMarkup() {
        #expect(HTMLEscaping.escape("a < b & \"c\" > d") == "a &lt; b &amp; &quot;c&quot; &gt; d")
    }

    @Test func unescapesNamedAndNumericEntities() {
        #expect(HTMLEscaping.unescape("C &amp; D &lt;x&gt; &quot;q&quot; &#39;s&#39; &#x41;") == "C & D <x> \"q\" 's' A")
    }

    @Test func leavesUnknownEntitiesAlone() {
        #expect(HTMLEscaping.unescape("&bogus; & plain") == "&bogus; & plain")
    }
}
```

Add to `MarkdownRendererTests`:

```swift
    @Test func rendersFootnotesWithClosedBackref() {
        let html = renderer.renderBody("Note[^1]\n\n[^1]: Footnote text\n")
        #expect(html.contains("<section class=\"footnotes\""))
        #expect(html.contains("aria-label=\"Back to reference 1\">↩</a>"))
    }
```

- [ ] **Step 2: Run, expect failure** (`HTMLEscaping` undefined; footnote test fails on `1↩</a>`).

- [ ] **Step 3: Implement**

`HTMLEscaping.swift`:

```swift
import Foundation

enum HTMLEscaping {
    static func escape(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            case "\"": output += "&quot;"
            default: output.append(character)
            }
        }
        return output
    }

    /// Decodes the entities cmark emits (`&amp; &lt; &gt; &quot; &#39;`) plus numeric references.
    static func unescape(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&" {
                let window = text[index...].prefix(12)
                if let semicolon = window.firstIndex(of: ";"),
                   let decoded = decode(entity: text[text.index(after: index)..<semicolon]) {
                    output.append(decoded)
                    index = text.index(after: semicolon)
                    continue
                }
            }
            output.append(text[index])
            index = text.index(after: index)
        }
        return output
    }

    private static func decode(entity: Substring) -> Character? {
        switch entity {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        default:
            guard entity.hasPrefix("#") else { return nil }
            let number = entity.dropFirst()
            let value: UInt32?
            if number.hasPrefix("x") || number.hasPrefix("X") {
                value = UInt32(number.dropFirst(), radix: 16)
            } else {
                value = UInt32(number)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return Character(scalar)
        }
    }
}
```

`HTMLFixups.swift`:

```swift
import Foundation

enum HTMLFixups {
    /// swift-cmark (branch gfm, src/html.c) emits `aria-label="Back to reference 1↩</a>`
    /// for the first footnote back-reference, missing the closing `">`.
    private static let brokenBackref = try! NSRegularExpression(
        pattern: #"(aria-label="Back to reference [^"<>]*)(↩</a>)"#
    )

    static func repairFootnoteBackrefs(in html: String) -> String {
        let range = NSRange(html.startIndex..., in: html)
        return brokenBackref.stringByReplacingMatches(in: html, range: range, withTemplate: "$1\">$2")
    }
}
```

`MarkdownRenderer.renderBody`:

```swift
    public func renderBody(_ markdown: String) -> String {
        HTMLFixups.repairFootnoteBackrefs(in: GFMRenderer.render(markdown))
    }
```

- [ ] **Step 4: Run tests** — expect all pass.

---

### Task 3: Front matter

**Files:**
- Create: `Packages/UncialCore/Sources/UncialCore/FrontMatter.swift`
- Modify: `MarkdownRenderer.swift`
- Test: `Packages/UncialCore/Tests/UncialCoreTests/FrontMatterTests.swift`, add test to `MarkdownRendererTests.swift`

**Interfaces:**
- Produces: `FrontMatter.split(_:) -> (frontMatter: String?, body: String)`, internal `FrontMatter.renderBlock(_:) -> String`.

- [ ] **Step 1: Failing tests**

```swift
import Testing
@testable import UncialCore

@Suite struct FrontMatterTests {
    @Test func splitsLeadingBlock() {
        let (frontMatter, body) = FrontMatter.split("---\ntitle: X\ntags: [a]\n---\n# Hi\n")
        #expect(frontMatter == "title: X\ntags: [a]")
        #expect(body == "# Hi\n")
    }

    @Test func ignoresWithoutClosingDelimiter() {
        let text = "---\nnot front matter\n# Hi"
        let (frontMatter, body) = FrontMatter.split(text)
        #expect(frontMatter == nil)
        #expect(body == text)
    }

    @Test func ignoresWhenNotAtStart() {
        #expect(FrontMatter.split("# Hi\n---\nx: 1\n---\n").frontMatter == nil)
    }

    @Test func acceptsDotsClosingAndCRLF() {
        let (frontMatter, body) = FrontMatter.split("---\r\na: 1\r\n...\r\nBody")
        #expect(frontMatter == "a: 1")
        #expect(body == "Body")
    }

    @Test func stripsBOM() {
        #expect(FrontMatter.split("\u{FEFF}---\na: 1\n---\n").frontMatter == "a: 1")
    }

    @Test func rendersNonEmptyBlockEscaped() {
        #expect(FrontMatter.renderBlock("a: <b>") == "<pre class=\"front-matter\">a: &lt;b&gt;</pre>\n")
        #expect(FrontMatter.renderBlock("  \n") == "")
    }
}
```

Add to `MarkdownRendererTests`:

```swift
    @Test func rendersFrontMatterAsBlock() {
        let html = renderer.renderBody("---\ntitle: Hi\n---\n# Body")
        #expect(html.hasPrefix("<pre class=\"front-matter\">title: Hi</pre>"))
        #expect(html.contains("<h1>Body</h1>"))
    }
```

- [ ] **Step 2: Run, expect failure.**

- [ ] **Step 3: Implement**

```swift
import Foundation

/// YAML front matter: a leading block delimited by `---` lines (closing may be `---` or `...`).
public enum FrontMatter {
    public static func split(_ markdown: String) -> (frontMatter: String?, body: String) {
        var text = Substring(markdown)
        if text.hasPrefix("\u{FEFF}") { text = text.dropFirst() }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, isDelimiter(first, allowDots: false) else {
            return (nil, String(text))
        }
        guard let closing = lines.dropFirst().firstIndex(where: { isDelimiter($0, allowDots: true) }) else {
            return (nil, String(text))
        }
        let frontMatter = lines[1..<closing]
            .map { $0.hasSuffix("\r") ? $0.dropLast() : $0 }
            .joined(separator: "\n")
        lines.removeSubrange(0...closing)
        return (frontMatter, lines.joined(separator: "\n"))
    }

    static func renderBlock(_ frontMatter: String) -> String {
        let trimmed = frontMatter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "<pre class=\"front-matter\">\(HTMLEscaping.escape(trimmed))</pre>\n"
    }

    private static func isDelimiter(_ line: Substring, allowDots: Bool) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "---" || (allowDots && trimmed == "...")
    }
}
```

`MarkdownRenderer.renderBody`:

```swift
    public func renderBody(_ markdown: String) -> String {
        let (frontMatter, body) = FrontMatter.split(markdown)
        var html = HTMLFixups.repairFootnoteBackrefs(in: GFMRenderer.render(body))
        if let frontMatter {
            html = FrontMatter.renderBlock(frontMatter) + html
        }
        return html
    }
```

- [ ] **Step 4: Run tests** — expect pass.

---

### Task 4: Heading anchors

**Files:**
- Create: `Packages/UncialCore/Sources/UncialCore/HeadingAnchors.swift`
- Modify: `MarkdownRenderer.swift`
- Test: `Packages/UncialCore/Tests/UncialCoreTests/HeadingAnchorsTests.swift`; update `rendersFrontMatterAsBlock` expectation to `<h1 id="body">Body</h1>`

**Interfaces:**
- Produces: `HeadingAnchors.addIDs(to html: String) -> String`, `HeadingAnchors.slug(for text: String) -> String`.

- [ ] **Step 1: Failing tests**

```swift
import Testing
@testable import UncialCore

@Suite struct HeadingAnchorsTests {
    @Test func slugFollowsGitHubRules() {
        #expect(HeadingAnchors.slug(for: "Hello, World!") == "hello-world")
        #expect(HeadingAnchors.slug(for: "C &amp; D") == "c--d")
        #expect(HeadingAnchors.slug(for: "<code>foo_bar</code> baz") == "foo_bar-baz")
        #expect(HeadingAnchors.slug(for: "Привет мир") == "привет-мир")
        #expect(HeadingAnchors.slug(for: "1.2 Release") == "12-release")
    }

    @Test func addsIDsAndDeduplicates() {
        let html = "<h1>Intro</h1>\n<h2>Setup</h2>\n<h2>Setup</h2>\n<h3 class=\"x\">Setup</h3>\n"
        let output = HeadingAnchors.addIDs(to: html)
        #expect(output.contains("<h1 id=\"intro\">Intro</h1>"))
        #expect(output.contains("<h2 id=\"setup\">Setup</h2>"))
        #expect(output.contains("<h2 id=\"setup-1\">Setup</h2>"))
        #expect(output.contains("<h3 id=\"setup-2\" class=\"x\">Setup</h3>"))
    }

    @Test func keepsExistingIDs() {
        let html = "<h2 id=\"custom\">Title</h2>"
        #expect(HeadingAnchors.addIDs(to: html) == html)
    }
}
```

Add to `MarkdownRendererTests`:

```swift
    @Test func rendersHeadingWithAnchor() {
        #expect(renderer.renderBody("# Hello World").contains("<h1 id=\"hello-world\">Hello World</h1>"))
    }
```

- [ ] **Step 2: Run, expect failure.**

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Adds GitHub-style `id` attributes to headings so `[link](#section)` works.
public enum HeadingAnchors {
    private static let heading = try! NSRegularExpression(
        pattern: #"<h([1-6])(\s[^>]*)?>(.*?)</h\1>"#,
        options: [.dotMatchesLineSeparators, .caseInsensitive]
    )
    private static let tag = try! NSRegularExpression(pattern: #"<[^>]+>"#)
    private static let idAttribute = try! NSRegularExpression(pattern: #"\sid\s*="#, options: [.caseInsensitive])

    public static func addIDs(to html: String) -> String {
        let source = html as NSString
        var used: [String: Int] = [:]
        var output = ""
        var cursor = 0
        for match in heading.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let level = source.substring(with: match.range(at: 1))
            let attributes = match.range(at: 2).location == NSNotFound ? "" : source.substring(with: match.range(at: 2))
            let inner = source.substring(with: match.range(at: 3))
            let attributeRange = NSRange(location: 0, length: (attributes as NSString).length)
            if idAttribute.firstMatch(in: attributes, range: attributeRange) != nil {
                output += source.substring(with: match.range)
            } else {
                let base = slug(for: inner)
                let seen = used[base, default: 0]
                used[base] = seen + 1
                let id = seen == 0 ? base : "\(base)-\(seen)"
                output += "<h\(level) id=\"\(id)\"\(attributes)>\(inner)</h\(level)>"
            }
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        return output
    }

    /// GitHub's slug: strip tags, lowercase, keep letters/digits/marks/`_`/`-`, spaces → `-`.
    public static func slug(for text: String) -> String {
        let withoutTags = tag.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: ""
        )
        let plain = HTMLEscaping.unescape(withoutTags).lowercased()
        var slug = ""
        for scalar in plain.unicodeScalars {
            switch scalar {
            case " ":
                slug.append("-")
            case "-", "_":
                slug.unicodeScalars.append(scalar)
            default:
                let properties = scalar.properties
                let isMark: Bool
                switch properties.generalCategory {
                case .nonspacingMark, .spacingMark, .enclosingMark: isMark = true
                default: isMark = false
                }
                if properties.isAlphabetic || properties.numericType != nil || isMark {
                    slug.unicodeScalars.append(scalar)
                }
            }
        }
        return slug
    }
}
```

`MarkdownRenderer.renderBody`: after the footnote repair add `html = HeadingAnchors.addIDs(to: html)` (before prepending front matter).

- [ ] **Step 4: Run tests** — expect pass.

---

### Task 5: Image inliner

**Files:**
- Create: `Packages/UncialCore/Sources/UncialCore/ImageInliner.swift`
- Test: `Packages/UncialCore/Tests/UncialCoreTests/ImageInlinerTests.swift`

**Interfaces:**
- Produces: `ImageInliner(baseURL: URL, maxBytes: Int = 20 * 1024 * 1024)`, `inline(_ html: String) -> String`.

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Testing
@testable import UncialCore

@Suite struct ImageInlinerTests {
    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uncial-img-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("img"), withIntermediateDirectories: true)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        try png.write(to: directory.appendingPathComponent("img/dot.png"))
        try Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8).write(to: directory.appendingPathComponent("img/my icon.svg"))
        return directory
    }

    @Test func inlinesRelativeImages() throws {
        let inliner = ImageInliner(baseURL: try fixtureDirectory().appendingPathComponent("README.md"))
        let html = "<p><img src=\"img/dot.png\" alt=\"dot\" /> <img src='./img/my%20icon.svg'></p>"
        let output = inliner.inline(html)
        #expect(output.contains("<img src=\"data:image/png;base64,iVBORw0KGgo"))
        #expect(output.contains("alt=\"dot\" />"))
        #expect(output.contains("<img src='data:image/svg+xml;base64,"))
    }

    @Test func leavesRemoteMissingOversizedAndDataAlone() throws {
        let inliner = ImageInliner(baseURL: try fixtureDirectory().appendingPathComponent("README.md"), maxBytes: 10)
        let html = "<img src=\"https://example.com/a.png\"><img src=\"img/missing.png\"><img src=\"img/dot.png\"><img src=\"data:image/png;base64,AAAA\">"
        #expect(inliner.inline(html) == html)
    }

    @Test func stripsQueryAndFragment() throws {
        let inliner = ImageInliner(baseURL: try fixtureDirectory().appendingPathComponent("README.md"))
        let output = inliner.inline("<img src=\"img/dot.png?raw=true#gh-light-mode-only\">")
        #expect(output.hasPrefix("<img src=\"data:image/png;base64,"))
    }
}
```

- [ ] **Step 2: Run, expect failure.**

- [ ] **Step 3: Implement**

```swift
import Foundation
import UniformTypeIdentifiers

/// Rewrites relative `<img src>` references to `data:` URIs so previews work without file access.
public struct ImageInliner: Sendable {
    public let directoryURL: URL
    public let maxBytes: Int

    private static let imageSource = try! NSRegularExpression(
        pattern: #"(<img\b[^>]*?\bsrc\s*=\s*)(?:"([^"]*)"|'([^']*)')"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let scheme = try! NSRegularExpression(pattern: #"^[a-zA-Z][a-zA-Z0-9+.\-]*:"#)

    /// - Parameter baseURL: the document file (its directory is used) or a directory URL.
    public init(baseURL: URL, maxBytes: Int = 20 * 1024 * 1024) {
        self.directoryURL = baseURL.hasDirectoryPath ? baseURL : baseURL.deletingLastPathComponent()
        self.maxBytes = maxBytes
    }

    public func inline(_ html: String) -> String {
        let source = html as NSString
        var output = ""
        var cursor = 0
        for match in Self.imageSource.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let prefix = source.substring(with: match.range(at: 1))
            let doubleQuoted = match.range(at: 2).location != NSNotFound
            let value = source.substring(with: doubleQuoted ? match.range(at: 2) : match.range(at: 3))
            let quote = doubleQuoted ? "\"" : "'"
            output += prefix + quote + (dataURI(for: value) ?? value) + quote
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        return output
    }

    /// Resolves `source` against the directory and returns a data URI, or nil when it should be left alone.
    func dataURI(for source: String) -> String? {
        guard let fileURL = localFileURL(for: source),
              let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxBytes,
              let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType,
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    func localFileURL(for source: String) -> URL? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else { return nil }
        let range = NSRange(location: 0, length: (trimmed as NSString).length)
        if Self.scheme.firstMatch(in: trimmed, range: range) != nil {
            guard trimmed.lowercased().hasPrefix("file:"), let url = URL(string: trimmed), url.isFileURL else { return nil }
            return URL(fileURLWithPath: url.path)
        }
        let allowed = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: "%?#"))
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        guard let resolved = URL(string: encoded, relativeTo: directoryURL) else { return nil }
        return URL(fileURLWithPath: resolved.path)
    }
}
```

- [ ] **Step 4: Run tests** — expect pass.

---

### Task 6: Stylesheet, full document, text decoding

**Files:**
- Create: `Packages/UncialCore/Sources/UncialCore/Stylesheet.swift`
- Create: `Packages/UncialCore/Sources/UncialCore/HTMLDocument.swift`
- Create: `Packages/UncialCore/Sources/UncialCore/MarkdownText.swift`
- Modify: `MarkdownRenderer.swift` (add `renderDocument`)
- Test: add to `MarkdownRendererTests.swift`; create `MarkdownTextTests.swift`

**Interfaces:**
- Produces: `MarkdownRenderer.renderDocument(_ markdown: String, title: String, baseURL: URL? = nil) -> String`, `MarkdownText.decode(_ data: Data) -> String`, `Stylesheet.css`.

- [ ] **Step 1: Failing tests**

Add to `MarkdownRendererTests`:

```swift
    @Test func documentWrapsBodyWithStyleAndTitle() {
        let html = renderer.renderDocument("# T", title: "A <B> & C.md")
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<meta name=\"color-scheme\" content=\"light dark\">"))
        #expect(html.contains("<title>A &lt;B&gt; &amp; C.md</title>"))
        #expect(html.contains("<style>"))
        #expect(html.contains("prefers-color-scheme: dark"))
        #expect(html.contains("<article class=\"markdown-body\">\n<h1 id=\"t\">T</h1>"))
    }

    @Test func documentInlinesImagesRelativeToBaseURL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uncial-doc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x47, 0x49, 0x46]).write(to: directory.appendingPathComponent("a.gif"))
        let html = renderer.renderDocument("![a](a.gif)", title: "t", baseURL: directory.appendingPathComponent("doc.md"))
        #expect(html.contains("<img src=\"data:image/gif;base64,R0lG\" alt=\"a\" />"))
    }
```

(`MarkdownRendererTests.swift` needs `import Foundation` for this.)

`MarkdownTextTests.swift`:

```swift
import Foundation
import Testing
@testable import UncialCore

@Suite struct MarkdownTextTests {
    @Test func decodesUTF8AndStripsBOM() {
        #expect(MarkdownText.decode(Data([0xEF, 0xBB, 0xBF] + Array("# Hi".utf8))) == "# Hi")
        #expect(MarkdownText.decode(Data("# Hi".utf8)) == "# Hi")
    }

    @Test func decodesInvalidBytesLossily() {
        let text = MarkdownText.decode(Data([0x23, 0x20, 0xFF, 0xFE, 0x41]))
        #expect(text.hasPrefix("# "))
        #expect(text.hasSuffix("A"))
    }

    @Test func decodesUTF16WithBOM() {
        #expect(MarkdownText.decode("# Hi".data(using: .utf16)!) == "# Hi")
    }
}
```

- [ ] **Step 2: Run, expect failure.**

- [ ] **Step 3: Implement**

`MarkdownText.swift`:

```swift
import Foundation

public enum MarkdownText {
    /// UTF-8 (BOM stripped), UTF-16 when a BOM says so, otherwise lossy UTF-8.
    public static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data.dropFirst(3), encoding: .utf8) {
            return text
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }
}
```

`HTMLDocument.swift`:

```swift
enum HTMLDocument {
    static func wrap(body: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(HTMLEscaping.escape(title))</title>
        <style>
        \(Stylesheet.css)
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }
}
```

`Stylesheet.swift`:

```swift
/// GitHub-like styling. Light palette on `:root`, dark palette under `prefers-color-scheme: dark`.
public enum Stylesheet {
    public static let css = #"""
    :root {
      color-scheme: light dark;
      --bg: #ffffff;
      --fg: #1f2328;
      --muted: #59636e;
      --border: #d1d9e0;
      --border-muted: #d8dee4;
      --accent: #0969da;
      --code-bg: #f6f8fa;
      --row-alt: #f6f8fa;
      --mark: #fff8c5;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0d1117;
        --fg: #f0f6fc;
        --muted: #9198a1;
        --border: #3d444d;
        --border-muted: #30363d;
        --accent: #4493f8;
        --code-bg: #151b23;
        --row-alt: #151b23;
        --mark: #3a2d00;
      }
    }
    html, body { margin: 0; padding: 0; background: var(--bg); color: var(--fg); }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif, "Apple Color Emoji";
      font-size: 16px;
      line-height: 1.5;
      -webkit-text-size-adjust: 100%;
      word-wrap: break-word;
    }
    .markdown-body { max-width: 860px; margin: 0 auto; padding: 32px 40px 64px; box-sizing: border-box; }
    @media (max-width: 640px) { .markdown-body { padding: 16px; } }
    .markdown-body > :first-child { margin-top: 0; }
    .markdown-body > :last-child { margin-bottom: 0; }
    h1, h2, h3, h4, h5, h6 { margin-top: 24px; margin-bottom: 16px; font-weight: 600; line-height: 1.25; }
    h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--border-muted); }
    h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--border-muted); }
    h3 { font-size: 1.25em; }
    h4 { font-size: 1em; }
    h5 { font-size: .875em; }
    h6 { font-size: .85em; color: var(--muted); }
    p, blockquote, ul, ol, dl, table, pre, details { margin-top: 0; margin-bottom: 16px; }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    img { max-width: 100%; box-sizing: content-box; }
    code, pre, kbd, samp { font-family: ui-monospace, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace; }
    code { padding: .2em .4em; margin: 0; font-size: 85%; background: var(--code-bg); border-radius: 6px; white-space: break-spaces; }
    pre { padding: 16px; overflow: auto; font-size: 85%; line-height: 1.45; background: var(--code-bg); border-radius: 6px; }
    pre code { padding: 0; margin: 0; font-size: 100%; background: transparent; border: 0; white-space: pre; word-break: normal; }
    blockquote { margin: 0 0 16px; padding: 0 1em; color: var(--muted); border-left: .25em solid var(--border); }
    blockquote > :first-child { margin-top: 0; }
    blockquote > :last-child { margin-bottom: 0; }
    ul, ol { padding-left: 2em; }
    ul ul, ul ol, ol ol, ol ul { margin-top: 0; margin-bottom: 0; }
    li + li { margin-top: .25em; }
    li > p { margin-top: 16px; }
    li:has(> input[type=checkbox]) { list-style: none; margin-left: -1.5em; }
    li > input[type=checkbox] { margin: 0 .4em .25em 0; vertical-align: middle; }
    table { border-spacing: 0; border-collapse: collapse; display: block; width: max-content; max-width: 100%; overflow: auto; }
    th, td { padding: 6px 13px; border: 1px solid var(--border); }
    th { font-weight: 600; }
    tr { background: var(--bg); border-top: 1px solid var(--border-muted); }
    tbody tr:nth-child(2n) { background: var(--row-alt); }
    hr { height: .25em; padding: 0; margin: 24px 0; background: var(--border); border: 0; }
    details summary { cursor: pointer; font-weight: 600; }
    mark { background: var(--mark); color: inherit; }
    kbd {
      display: inline-block; padding: 3px 5px; font-size: 11px; line-height: 10px; vertical-align: middle;
      background: var(--code-bg); border: 1px solid var(--border); border-radius: 6px; box-shadow: inset 0 -1px 0 var(--border);
    }
    sup.footnote-ref { font-size: 75%; }
    section.footnotes { margin-top: 32px; padding-top: 8px; font-size: 85%; color: var(--muted); border-top: 1px solid var(--border); }
    section.footnotes p { margin-bottom: 8px; }
    pre.front-matter { color: var(--muted); font-size: 80%; background: transparent; border: 1px dashed var(--border); }
    :target { scroll-margin-top: 16px; }
    """#
}
```

`MarkdownRenderer.renderDocument`:

```swift
    /// Standalone HTML page: CSS inlined, relative images under `baseURL` inlined as data URIs.
    public func renderDocument(_ markdown: String, title: String, baseURL: URL? = nil) -> String {
        var body = renderBody(markdown)
        if let baseURL {
            body = ImageInliner(baseURL: baseURL).inline(body)
        }
        return HTMLDocument.wrap(body: body, title: title)
    }
```

- [ ] **Step 4: Run tests** — expect pass.

- [ ] **Step 5: Visual check.** Render the README (Task 12 writes it; use any sample) to `scratchpad/preview.html` with a tiny `swift run`-less script (see Task 12 Step 4) and open in a browser in light and dark; adjust CSS if anything is unreadable.

---

### Task 7: FileWatcher

**Files:**
- Create: `Packages/UncialCore/Sources/UncialCore/FileWatcher.swift`
- Test: `Packages/UncialCore/Tests/UncialCoreTests/FileWatcherTests.swift`

**Interfaces:**
- Produces: `FileWatcher(url: URL, debounce: TimeInterval = 0.1, onChange: @escaping @MainActor @Sendable () -> Void)`, `start()`, `stop()`.

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Testing
@testable import UncialCore

@MainActor final class ChangeCounter {
    private(set) var value = 0
    nonisolated init() {}
    func increment() { value += 1 }
}

@Suite struct FileWatcherTests {
    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uncial-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("doc.md")
        try Data("# one\n".utf8).write(to: file)
        return file
    }

    /// Starts a watcher, performs `mutation`, waits `settle`, returns how many callbacks fired.
    private func changes(on file: URL, settle: Duration, mutation: @escaping @Sendable () throws -> Void) async throws -> Int {
        let counter = ChangeCounter()
        let watcher = FileWatcher(url: file, debounce: 0.05) { counter.increment() }
        watcher.start()
        try await Task.sleep(for: .milliseconds(100))
        try mutation()
        try await Task.sleep(for: settle)
        watcher.stop()
        return await counter.value
    }

    @Test func firesOnInPlaceWrite() async throws {
        let file = try temporaryFile()
        let count = try await changes(on: file, settle: .milliseconds(400)) {
            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("# two\n".utf8))
            try handle.close()
        }
        #expect(count == 1)
    }

    @Test func firesOnAtomicReplace() async throws {
        let file = try temporaryFile()
        let count = try await changes(on: file, settle: .milliseconds(600)) {
            let temporary = file.deletingLastPathComponent().appendingPathComponent("doc.md.tmp")
            try Data("# three\n".utf8).write(to: temporary)
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
        }
        #expect(count >= 1)
    }

    @Test func coalescesBursts() async throws {
        let file = try temporaryFile()
        let count = try await changes(on: file, settle: .milliseconds(400)) {
            let handle = try FileHandle(forWritingTo: file)
            for line in 0..<5 {
                try handle.seekToEnd()
                try handle.write(contentsOf: Data("line \(line)\n".utf8))
            }
            try handle.close()
        }
        #expect(count == 1)
    }

    @Test func doesNotFireWithoutChanges() async throws {
        let file = try temporaryFile()
        let count = try await changes(on: file, settle: .milliseconds(300)) {}
        #expect(count == 0)
    }
}
```

- [ ] **Step 2: Run, expect failure.**

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Watches one file for content changes, surviving atomic saves (write-to-temp + rename).
public final class FileWatcher: @unchecked Sendable {
    public typealias ChangeHandler = @MainActor @Sendable () -> Void

    private let url: URL
    private let debounce: TimeInterval
    private let onChange: ChangeHandler
    private let queue = DispatchQueue(label: "com.maksimradaev.uncial.filewatcher")
    private var source: DispatchSourceFileSystemObject?
    private var pendingChange: DispatchWorkItem?
    private var reopenAttempts = 0
    private var isRunning = false

    private static let maxReopenAttempts = 20
    private static let reopenInterval: TimeInterval = 0.05

    public init(url: URL, debounce: TimeInterval = 0.1, onChange: @escaping ChangeHandler) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit {
        source?.cancel()
        pendingChange?.cancel()
    }

    public func start() {
        queue.async {
            guard !self.isRunning else { return }
            self.isRunning = true
            self.reopenAttempts = 0
            if !self.arm() { self.scheduleReopen() }
        }
    }

    public func stop() {
        queue.async {
            self.isRunning = false
            self.disarm()
            self.pendingChange?.cancel()
            self.pendingChange = nil
        }
    }

    // MARK: - Queue-confined

    /// Opens the file and installs a vnode source. Returns false when the file can't be opened.
    private func arm() -> Bool {
        disarm()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.handleEvent() }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.activate()
        return true
    }

    private func disarm() {
        source?.cancel()
        source = nil
    }

    private func handleEvent() {
        guard let source else { return }
        let flags = source.data
        if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
            // The path now points at a new inode (atomic save) or nothing; re-arm on the path.
            disarm()
            reopenAttempts = 0
            scheduleReopen()
        } else {
            scheduleChange()
        }
    }

    private func scheduleReopen() {
        guard isRunning, reopenAttempts < Self.maxReopenAttempts else { return }
        reopenAttempts += 1
        queue.asyncAfter(deadline: .now() + Self.reopenInterval) { [weak self] in
            guard let self, self.isRunning else { return }
            if self.arm() {
                self.reopenAttempts = 0
                self.scheduleChange()
            } else {
                self.scheduleReopen()
            }
        }
    }

    private func scheduleChange() {
        pendingChange?.cancel()
        let onChange = self.onChange
        let work = DispatchWorkItem {
            Task { @MainActor in onChange() }
        }
        pendingChange = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
```

- [ ] **Step 4: Run tests** — expect all package tests pass (run twice to check for flakiness).

---

### Task 8: App source code

**Files:**
- Delete: `uncial/Item.swift`, `uncial/ContentView.swift`, `uncial/uncialApp.swift`
- Create: `uncial/UncialApp.swift`, `uncial/ReloadAction.swift`, `uncial/MarkdownDocument.swift`, `uncial/DocumentViewModel.swift`, `uncial/DocumentView.swift`, `uncial/WebView.swift`, `uncial/LinkOpener.swift`
- Modify: `uncial/Info.plist`, `uncialTests/uncialTests.swift`

**Interfaces:**
- Consumes: `MarkdownRenderer`, `MarkdownText`, `FileWatcher` from `UncialCore`.
- Produces: `MarkdownDocument`, `DocumentViewModel`, `DocumentView`, `WebView`, `LinkOpener`, `FocusedValues.reloadDocument`.

Notes for the implementer: the app target builds in Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every type is main-actor isolated unless marked `nonisolated`. `FileDocument` is read on a background thread, so `MarkdownDocument` is `nonisolated`.

- [ ] **Step 1: Delete the SwiftData template files**

```bash
rm uncial/Item.swift uncial/ContentView.swift uncial/uncialApp.swift
```

- [ ] **Step 2: Write the app files**

`uncial/UncialApp.swift`:

```swift
import SwiftUI

@main
struct UncialApp: App {
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
    }
}
```

`uncial/ReloadAction.swift`:

```swift
import SwiftUI

/// Re-reads and re-renders the focused document. Exposed through focused values for the View ▸ Reload menu.
struct ReloadAction {
    let run: @MainActor () -> Void
}

private struct ReloadDocumentKey: FocusedValueKey {
    typealias Value = ReloadAction
}

extension FocusedValues {
    var reloadDocument: ReloadAction? {
        get { self[ReloadDocumentKey.self] }
        set { self[ReloadDocumentKey.self] = newValue }
    }
}
```

`uncial/MarkdownDocument.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers
import UncialCore

/// Read-only document model. Decoding happens off the main thread, hence `nonisolated`.
nonisolated struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdown]

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = MarkdownText.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

extension UTType {
    nonisolated static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}
```

`uncial/DocumentViewModel.swift`:

```swift
import Foundation
import Observation
import UncialCore

@Observable
final class DocumentViewModel {
    let fileURL: URL?
    private(set) var html = ""
    private(set) var error: String?

    private let renderer = MarkdownRenderer()
    private var watcher: FileWatcher?
    private var generation = 0

    init(fileURL: URL?, initialText: String) {
        self.fileURL = fileURL
        render(initialText)
        watch()
    }

    /// Re-reads the file from disk and re-renders. Stale results are dropped.
    func reload() {
        guard let fileURL else { return }
        generation += 1
        let generation = generation
        let renderer = renderer
        let title = fileURL.lastPathComponent
        Task.detached(priority: .userInitiated) {
            let result: Result<String, Error>
            do {
                let data = try Data(contentsOf: fileURL)
                result = .success(renderer.renderDocument(MarkdownText.decode(data), title: title, baseURL: fileURL))
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                switch result {
                case .success(let html):
                    self.html = html
                    self.error = nil
                case .failure(let error):
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func render(_ text: String) {
        generation += 1
        let generation = generation
        let renderer = renderer
        let title = fileURL?.lastPathComponent ?? "Markdown"
        let baseURL = fileURL
        Task.detached(priority: .userInitiated) {
            let html = renderer.renderDocument(text, title: title, baseURL: baseURL)
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                self.html = html
            }
        }
    }

    private func watch() {
        guard let fileURL else { return }
        let watcher = FileWatcher(url: fileURL) { [weak self] in self?.reload() }
        watcher.start()
        self.watcher = watcher
    }
}
```

`uncial/DocumentView.swift`:

```swift
import SwiftUI

struct DocumentView: View {
    @State private var model: DocumentViewModel

    init(document: MarkdownDocument, fileURL: URL?) {
        _model = State(initialValue: DocumentViewModel(fileURL: fileURL, initialText: document.text))
    }

    var body: some View {
        content
            .frame(minWidth: 480, minHeight: 320)
            .focusedSceneValue(\.reloadDocument, ReloadAction { model.reload() })
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.error, model.html.isEmpty {
            ContentUnavailableView("Can't Read Document", systemImage: "doc.text.magnifyingglass", description: Text(error))
        } else {
            WebView(html: model.html, baseURL: model.fileURL?.deletingLastPathComponent())
        }
    }
}
```

`uncial/WebView.swift`:

```swift
import SwiftUI
import WebKit

/// Shows rendered HTML. Content JavaScript is off; the document is untrusted input.
struct WebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = .windowBackgroundColor
        #if DEBUG
        webView.isInspectable = true
        #endif
        context.coordinator.webView = webView
        context.coordinator.show(html: html, baseURL: baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.show(html: html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        private var currentHTML: String?
        private var pendingScrollY: Double?

        func show(html: String, baseURL: URL?) {
            guard html != currentHTML, let webView else { return }
            let isFirstLoad = currentHTML == nil
            currentHTML = html
            if isFirstLoad {
                webView.loadHTMLString(html, baseURL: baseURL)
                return
            }
            webView.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
                self?.pendingScrollY = value as? Double
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let scrollY = pendingScrollY else { return }
            pendingScrollY = nil
            webView.evaluateJavaScript("window.scrollTo(0, \(scrollY));", completionHandler: nil)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.fragment != nil, Self.withoutFragment(url) == webView.url.map(Self.withoutFragment) {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            LinkOpener.open(url)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                LinkOpener.open(url)
            }
            return nil
        }

        private static func withoutFragment(_ url: URL) -> String {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            components?.fragment = nil
            return components?.string ?? url.absoluteString
        }
    }
}
```

`uncial/LinkOpener.swift`:

```swift
import AppKit

/// External links go to the default browser; local Markdown files open in Uncial; other files open with their default app.
enum LinkOpener {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext"]

    static func open(_ url: URL) {
        guard url.isFileURL else {
            NSWorkspace.shared.open(url)
            return
        }
        let fileURL = URL(fileURLWithPath: url.path)
        guard markdownExtensions.contains(fileURL.pathExtension.lowercased()) else {
            NSWorkspace.shared.open(fileURL)
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { _, _, error in
            if error != nil {
                NSWorkspace.shared.open(fileURL)
            }
        }
    }
}
```

`uncial/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>Markdown Document</string>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>net.daringfireball.markdown</string>
			</array>
		</dict>
	</array>
	<key>UTImportedTypeDeclarations</key>
	<array>
		<dict>
			<key>UTTypeConformsTo</key>
			<array>
				<string>public.plain-text</string>
			</array>
			<key>UTTypeDescription</key>
			<string>Markdown Document</string>
			<key>UTTypeIdentifier</key>
			<string>net.daringfireball.markdown</string>
			<key>UTTypeTagSpecification</key>
			<dict>
				<key>public.filename-extension</key>
				<array>
					<string>md</string>
					<string>markdown</string>
					<string>mdown</string>
					<string>mkd</string>
					<string>mkdn</string>
					<string>mdwn</string>
					<string>mdtxt</string>
					<string>mdtext</string>
				</array>
				<key>public.mime-type</key>
				<array>
					<string>text/markdown</string>
					<string>text/x-markdown</string>
				</array>
			</dict>
		</dict>
	</array>
</dict>
</plist>
```

`uncialTests/uncialTests.swift`:

```swift
import Testing
import UniformTypeIdentifiers
@testable import Uncial

struct UncialTests {
    @Test func markdownTypeIsTheStandardIdentifier() {
        #expect(UTType.markdown.identifier == "net.daringfireball.markdown")
        #expect(MarkdownDocument.readableContentTypes == [.markdown])
    }

    @Test func linkOpenerKnowsMarkdownExtensions() {
        #expect(LinkOpener.markdownExtensions.contains("md"))
        #expect(!LinkOpener.markdownExtensions.contains("txt"))
    }
}
```

- [ ] **Step 3: Do not build yet** — the project does not link `UncialCore` until Task 9.

---

### Task 9: Project surgery — package link, settings, product name

**Files:**
- Modify: `uncial.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: app target links `UncialCore`; all targets build for macOS 14.0; app bundle is `Uncial.app`.

Apply with a Python script that asserts each anchor exists exactly once before replacing (fail loudly otherwise). New object ids use the prefix `5A1C1A1E00000000000000`.

- [ ] **Step 1: Add the package reference and product dependency objects**

Insert before `/* Begin XCBuildConfiguration section */`... no — Xcode groups by section name; add these two new sections right before `/* Begin XCConfigurationList section */` is wrong too. Add them at the very end of `objects`, before the closing `	};\n	rootObject`:

```
/* Begin XCLocalSwiftPackageReference section */
		5A1C1A1E000000000000000B /* XCLocalSwiftPackageReference "Packages/UncialCore" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = Packages/UncialCore;
		};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		5A1C1A1E000000000000000C /* UncialCore */ = {
			isa = XCSwiftPackageProductDependency;
			productName = UncialCore;
		};
		5A1C1A1E000000000000000D /* UncialCore */ = {
			isa = XCSwiftPackageProductDependency;
			productName = UncialCore;
		};
/* End XCSwiftPackageProductDependency section */
```

- [ ] **Step 2: Add a `PBXBuildFile` section (the project has none yet)** before `/* Begin PBXContainerItemProxy section */`:

```
/* Begin PBXBuildFile section */
		5A1C1A1E000000000000000E /* UncialCore in Frameworks */ = {isa = PBXBuildFile; productRef = 5A1C1A1E000000000000000C /* UncialCore */; };
		5A1C1A1E000000000000000F /* UncialCore in Frameworks */ = {isa = PBXBuildFile; productRef = 5A1C1A1E000000000000000D /* UncialCore */; };
		5A1C1A1E0000000000000013 /* UncialQuickLook.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = 5A1C1A1E0000000000000001 /* UncialQuickLook.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
/* End PBXBuildFile section */
```

- [ ] **Step 3: Link the package into the app target**

In `22DDDE0B304C354F00A461AF /* Frameworks */` (the first Frameworks phase), replace the empty `files = (\n\t\t\t);` with:

```
			files = (
				5A1C1A1E000000000000000E /* UncialCore in Frameworks */,
			);
```

In the `uncial` native target replace `packageProductDependencies = (\n\t\t\t);` with:

```
			packageProductDependencies = (
				5A1C1A1E000000000000000C /* UncialCore */,
			);
```

In the `PBXProject` object add after `minimizedProjectReferenceProxies = 1;`:

```
			packageReferences = (
				5A1C1A1E000000000000000B /* XCLocalSwiftPackageReference "Packages/UncialCore" */,
			);
```

- [ ] **Step 4: Settings**

- Replace every `MACOSX_DEPLOYMENT_TARGET = 26.5;` with `MACOSX_DEPLOYMENT_TARGET = 14.0;` (project Debug/Release and uncialTests Debug/Release — 4 occurrences).
- In both app configurations (`22DDDE32…` Debug and `22DDDE33…` Release): `ENABLE_APP_SANDBOX = YES;` → `ENABLE_APP_SANDBOX = NO;`, `ENABLE_USER_SELECTED_FILES = readwrite;` → `ENABLE_USER_SELECTED_FILES = readonly;`, `PRODUCT_NAME = "$(TARGET_NAME)";` → `PRODUCT_NAME = Uncial;`, and add `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.productivity";` after `INFOPLIST_KEY_NSHumanReadableCopyright = "";`. Do these replacements only inside the two app configuration blocks (slice the text between `22DDDE32304C355000A461AF /* Debug */ = {` and `22DDDE34304C355000A461AF /* Debug */ = {`).
- In both `uncialTests` configurations replace `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/uncial.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/uncial";` with `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Uncial.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Uncial";`.

- [ ] **Step 5: Build the app**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project uncial.xcodeproj -scheme uncial -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error|warning: .*uncial/|BUILD"
```
Expected: `** BUILD SUCCEEDED **`, `build/Build/Products/Debug/Uncial.app` exists. (The extension target from Task 10 is not referenced yet, so the `PBXBuildFile` for the appex is dangling but harmless; Task 10 completes it.)

---

### Task 10: Quick Look extension target

**Files:**
- Create: `UncialQuickLook/PreviewProvider.swift`, `UncialQuickLook/Info.plist`
- Modify: `uncial.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `MarkdownRenderer.renderDocument`, `MarkdownText.decode`.
- Produces: `Uncial.app/Contents/PlugIns/UncialQuickLook.appex` registered for `com.apple.quicklook.preview`.

- [ ] **Step 1: Extension sources**

`UncialQuickLook/PreviewProvider.swift`:

```swift
import Cocoa
import Quartz
import UniformTypeIdentifiers
import UncialCore

/// Data-based Quick Look preview: returns the rendered document as HTML.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let fileURL = request.fileURL
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 800, height: 900)) { reply in
            let data = try Data(contentsOf: fileURL)
            let markdown = MarkdownText.decode(data)
            let html = MarkdownRenderer().renderDocument(markdown, title: fileURL.lastPathComponent, baseURL: fileURL)
            reply.stringEncoding = .utf8
            reply.title = fileURL.lastPathComponent
            return Data(html.utf8)
        }
    }
}
```

`UncialQuickLook/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionAttributes</key>
		<dict>
			<key>QLIsDataBasedPreview</key>
			<true/>
			<key>QLSupportedContentTypes</key>
			<array>
				<string>net.daringfireball.markdown</string>
			</array>
			<key>QLSupportsSearchableItems</key>
			<false/>
		</dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.quicklook.preview</string>
		<key>NSExtensionPrincipalClass</key>
		<string>$(PRODUCT_MODULE_NAME).PreviewProvider</string>
	</dict>
</dict>
</plist>
```

- [ ] **Step 2: pbxproj objects** (same Python-with-assertions approach)

Add to `PBXContainerItemProxy` section:

```
		5A1C1A1E0000000000000010 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 22DDDE06304C354F00A461AF /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 5A1C1A1E0000000000000004;
			remoteInfo = UncialQuickLook;
		};
```

New section before `/* Begin PBXFileReference section */`:

```
/* Begin PBXCopyFilesBuildPhase section */
		5A1C1A1E0000000000000012 /* Embed Foundation Extensions */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				5A1C1A1E0000000000000013 /* UncialQuickLook.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */
```

Add to `PBXFileReference`:

```
		5A1C1A1E0000000000000001 /* UncialQuickLook.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = UncialQuickLook.appex; sourceTree = BUILT_PRODUCTS_DIR; };
```

Add to `PBXFileSystemSynchronizedBuildFileExceptionSet`:

```
		5A1C1A1E0000000000000003 /* Exceptions for "UncialQuickLook" folder in "UncialQuickLook" target */ = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
			);
			target = 5A1C1A1E0000000000000004 /* UncialQuickLook */;
		};
```

Add to `PBXFileSystemSynchronizedRootGroup`:

```
		5A1C1A1E0000000000000002 /* UncialQuickLook */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				5A1C1A1E0000000000000003 /* Exceptions for "UncialQuickLook" folder in "UncialQuickLook" target */,
			);
			path = UncialQuickLook;
			sourceTree = "<group>";
		};
```

Add to `PBXFrameworksBuildPhase`:

```
		5A1C1A1E0000000000000007 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				5A1C1A1E000000000000000F /* UncialCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

Main group children: add `5A1C1A1E0000000000000002 /* UncialQuickLook */,` after the `uncialUITests` line. Products group children: add `5A1C1A1E0000000000000001 /* UncialQuickLook.appex */,`.

Add to `PBXNativeTarget`:

```
		5A1C1A1E0000000000000004 /* UncialQuickLook */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 5A1C1A1E0000000000000005 /* Build configuration list for PBXNativeTarget "UncialQuickLook" */;
			buildPhases = (
				5A1C1A1E0000000000000006 /* Sources */,
				5A1C1A1E0000000000000007 /* Frameworks */,
				5A1C1A1E0000000000000008 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				5A1C1A1E0000000000000002 /* UncialQuickLook */,
			);
			name = UncialQuickLook;
			packageProductDependencies = (
				5A1C1A1E000000000000000D /* UncialCore */,
			);
			productName = UncialQuickLook;
			productReference = 5A1C1A1E0000000000000001 /* UncialQuickLook.appex */;
			productType = "com.apple.product-type.app-extension";
		};
```

App target: `dependencies = (\n\t\t\t);` → include `5A1C1A1E0000000000000011 /* PBXTargetDependency */,`; `buildPhases` gets `5A1C1A1E0000000000000012 /* Embed Foundation Extensions */,` after the Resources phase.

`PBXProject`: add `5A1C1A1E0000000000000004 /* UncialQuickLook */,` to `targets`, and to `TargetAttributes`:

```
					5A1C1A1E0000000000000004 = {
						CreatedOnToolsVersion = 26.6;
					};
```

Add to `PBXResourcesBuildPhase` and `PBXSourcesBuildPhase` (empty phases, ids `…0008` and `…0006`, same shape as the existing ones).

Add to `PBXTargetDependency`:

```
		5A1C1A1E0000000000000011 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 5A1C1A1E0000000000000004 /* UncialQuickLook */;
			targetProxy = 5A1C1A1E0000000000000010 /* PBXContainerItemProxy */;
		};
```

Add to `XCBuildConfiguration` (Debug `…0009`, Release `…000A`, identical settings):

```
		5A1C1A1E0000000000000009 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = XWTLHG45H7;
				ENABLE_APP_SANDBOX = YES;
				ENABLE_HARDENED_RUNTIME = YES;
				ENABLE_USER_SELECTED_FILES = readonly;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = UncialQuickLook/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = "Uncial Quick Look";
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
					"@executable_path/../../../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.maksimradaev.uncial.QuickLook;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
```

Add to `XCConfigurationList`:

```
		5A1C1A1E0000000000000005 /* Build configuration list for PBXNativeTarget "UncialQuickLook" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				5A1C1A1E0000000000000009 /* Debug */,
				5A1C1A1E000000000000000A /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

- [ ] **Step 3: Build**

Run the Task 9 build command. Expected: `** BUILD SUCCEEDED **` and
`ls build/Build/Products/Debug/Uncial.app/Contents/PlugIns/UncialQuickLook.appex/Contents/MacOS/UncialQuickLook` exists.
Check: `plutil -p build/Build/Products/Debug/Uncial.app/Contents/PlugIns/UncialQuickLook.appex/Contents/Info.plist | grep -A8 NSExtension` shows the point identifier and content type; `codesign -d --entitlements - <appex>` shows `com.apple.security.app-sandbox`.

- [ ] **Step 4: `xcodebuild -list`** shows targets `uncial`, `uncialTests`, `uncialUITests`, `UncialQuickLook`.

---

### Task 11: Runtime verification (app + Quick Look)

**Files:** none (verification only; sample file in scratchpad).

- [ ] **Step 1: Sample document** at `<scratchpad>/sample/README.md` with headings, a TOC link, table, task list, code block, footnote, front matter, and `![dot](img/dot.png)` next to a real PNG.

- [ ] **Step 2: Launch the app**

```bash
APP=build/Build/Products/Debug/Uncial.app
open -a "$APP" <scratchpad>/sample/README.md
sleep 3; pgrep -x Uncial && echo running
```
Expected: process running; `log show --last 1m --predicate 'process == "Uncial"' --style compact | grep -iE "error|fault"` shows nothing fatal.

- [ ] **Step 3: Live reload** — append a heading to the sample, wait 1 s, confirm no crash (`pgrep -x Uncial`). Quit with `osascript -e 'quit app "Uncial"'`.

- [ ] **Step 4: Register and exercise the Quick Look extension**

```bash
APPEX="$PWD/$APP/Contents/PlugIns/UncialQuickLook.appex"
pluginkit -a "$APPEX"
pluginkit -m -v -p com.apple.quicklook.preview | grep -i uncial
qlmanage -r; qlmanage -r cache
qlmanage -p <scratchpad>/sample/README.md & sleep 5; kill %1
log show --last 1m --predicate 'process CONTAINS "QuickLook" OR process == "UncialQuickLook"' --style compact | grep -iE "uncial|error" | head
```
Expected: `pluginkit` lists `com.maksimradaev.uncial.QuickLook`; the preview window opens (rendered HTML, not plain text); no crash logs for `UncialQuickLook`.

- [ ] **Step 5: Unregister** the build-directory copy so a later `make install` is unambiguous: `pluginkit -r "$APPEX"`.

---

### Task 12: Makefile, README, .gitignore, icon

**Files:**
- Create: `Makefile`, `README.md`, `.gitignore`, `scripts/make-icon.swift`
- Modify: `uncial/Assets.xcassets/AppIcon.appiconset/Contents.json` (+ generated PNGs)

- [ ] **Step 1: `.gitignore`**

```
# Xcode
build/
DerivedData/
xcuserdata/
*.xcuserstate
*.xcscmblueprint
*.xccheckout

# SwiftPM
.build/
.swiftpm/
Packages/*/.build/

# macOS
.DS_Store
```

- [ ] **Step 2: `Makefile`**

```make
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

CONFIG ?= Release
BUILD_DIR ?= build
XCODEBUILD = xcodebuild -project uncial.xcodeproj -scheme uncial -derivedDataPath $(BUILD_DIR)
APP = $(BUILD_DIR)/Build/Products/$(CONFIG)/Uncial.app

.PHONY: build test core-test install uninstall icon clean

build:
	$(XCODEBUILD) -configuration $(CONFIG) build

core-test:
	cd Packages/UncialCore && swift test

test: core-test
	$(XCODEBUILD) -configuration Debug test -only-testing:uncialTests

install: build
	rm -rf /Applications/Uncial.app
	cp -R "$(APP)" /Applications/Uncial.app
	open -a /Applications/Uncial.app --background
	qlmanage -r
	qlmanage -r cache
	@echo "Installed. If Space in Finder still shows plain text, enable 'Uncial Quick Look' under System Settings > General > Login Items & Extensions > Quick Look."

uninstall:
	rm -rf /Applications/Uncial.app
	qlmanage -r

icon:
	swift scripts/make-icon.swift uncial/Assets.xcassets/AppIcon.appiconset

clean:
	rm -rf $(BUILD_DIR)
```

- [ ] **Step 3: Icon script** `scripts/make-icon.swift`

```swift
#!/usr/bin/env swift
// Generates the AppIcon set: a rounded dark tile with an uncial-style "U".
// Usage: swift scripts/make-icon.swift uncial/Assets.xcassets/AppIcon.appiconset
import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    let inset = size * 0.09
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: tile, xRadius: size * 0.2, yRadius: size * 0.2)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.22, green: 0.27, blue: 0.40, alpha: 1),
        ending: NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.17, alpha: 1)
    )!
    gradient.draw(in: path, angle: -90)
    let font = NSFont(name: "Baskerville-Bold", size: size * 0.66) ?? NSFont.systemFont(ofSize: size * 0.6, weight: .bold)
    let letter = NSAttributedString(string: "U", attributes: [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.86, alpha: 1),
    ])
    let textSize = letter.size()
    letter.draw(at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2 + size * 0.03))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for variant in variants {
    let name = variant.scale == 1 ? "icon_\(variant.points)x\(variant.points).png" : "icon_\(variant.points)x\(variant.points)@\(variant.scale)x.png"
    try! render(pixels: variant.points * variant.scale).write(to: outputDirectory.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(variant.scale)x", "size": "\(variant.points)x\(variant.points)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(outputDirectory.path)")
```

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/make-icon.swift uncial/Assets.xcassets/AppIcon.appiconset` then rebuild; `Uncial.app/Contents/Resources/AppIcon.icns` exists.

- [ ] **Step 4: README.md** — sections: What it is (one paragraph), Features (bullets from spec goals), Install (`make install`, or open the project in Xcode and run), Enabling the Quick Look extension (System Settings path, `qlmanage -r`, `pluginkit -m -p com.apple.quicklook.preview`), Usage (Open With, `open -a Uncial file.md`, ⌘R), How it works (three components, one line each), Development (`make core-test`, `make test`, `make build`, `make icon`, xcode-select note), Known limitations (no syntax highlighting, no Mermaid/math, app not sandboxed and why), License line left out.

- [ ] **Step 5: Final verification**

```bash
cd Packages/UncialCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | tail -3
cd ../.. && make build 2>&1 | grep -E "warning: .*(uncial|Uncial)/|error|BUILD"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project uncial.xcodeproj -scheme uncial -derivedDataPath build test -only-testing:uncialTests 2>&1 | grep -E "Test Suite|passed|failed|error" | tail -5
git status --short
```
Expected: all package tests pass; Release build succeeds without warnings in project code; unit tests pass; `git status` lists the new/changed files (nothing committed).

---

## Self-review

- **Spec coverage:** rendering pipeline (Tasks 1–6), watcher (7), app UI/links/reload/menu/Info.plist (8), project settings and sandbox/deployment/product name (9), extension (10), verification plan (11), Makefile/README/icon/.gitignore (12). Spec's "Nothing is committed" honored. Spec mentions an extension entitlements file; the plan uses the `ENABLE_APP_SANDBOX`/`ENABLE_USER_SELECTED_FILES` build settings instead (same generated entitlements, matches how the app target already works) — spec updated to say so.
- **Placeholders:** none; every code step has full content.
- **Type consistency:** `MarkdownRenderer.renderBody/renderDocument`, `MarkdownText.decode`, `FileWatcher(url:debounce:onChange:)`, `ReloadAction.run`, `FocusedValues.reloadDocument`, `LinkOpener.open`, `ImageInliner(baseURL:maxBytes:)` used identically across tasks.

## Execution notes (2026-09-05)

All twelve tasks executed in one autonomous session; nothing committed. Deviations from the plan:

- Task 3: `String.split(separator: "\n")` never splits CRLF text because Swift treats `"\r\n"` as one `Character`; `FrontMatter.split` matches both line endings explicitly.
- Task 6: added `a.footnote-backref { font-family: Menlo, … }` after the browser check showed the `↩` glyph falling into the emoji font.
- Tasks 9 and 10 were applied as one scripted pbxproj pass so no dangling `PBXBuildFile` ever existed; the app product reference was also renamed to `Uncial.app`.
- Task 8: `WebView.withoutFragment` is `nonisolated` (the compiler flagged the main-actor default isolation inside `Optional.map`). `UncialApp.swift` collides case-insensitively with the tracked template file, so the file keeps the name `uncial/uncialApp.swift`.
- Task 10: `PreviewProvider` logs to `Logger(subsystem: "com.maksimradaev.uncial", category: "quicklook")` for debugging.
- Task 11: `qlmanage -d 1` rejects its argument and `qlmanage -p -o` crashes inside ExtensionFoundation on this machine; the extension was verified by observing the `UncialQuickLook` process launch under `qlmanage -p` (no errors, no crash reports). Screen capture is blocked, so no Quick Look screenshot exists.
