import Foundation
import Testing
@testable import UncialCore

@Suite struct CodeHighlighterTests {
    /// The languages of https://dev.to/johnrushx/38-programming-languages-which-is-best-584f, by
    /// the names their fences carry, plus the formats READMEs use.
    static let languages = [
        "scratch", "basic", "python", "javascript", "java", "c", "cpp", "sql", "php", "swift", "kotlin", "r", "go", "dart",
        "csharp", "vbnet", "perl", "ruby", "scala", "objectivec", "x86asm", "armasm", "fortran", "lua", "rust", "julia",
        "typescript", "bash", "groovy", "fsharp", "elm", "elixir", "haskell", "prolog", "cobol", "matlab", "delphi", "clojure",
        "json", "yaml", "xml", "css", "markdown", "diff", "makefile", "dockerfile", "ini", "powershell", "plaintext", "console",
    ]

    static let aliases = [
        "py", "js", "jsx", "ts", "tsx", "c++", "h", "cs", "c#", "f#", "objective-c", "objc", "asm", "assembly", "nasm", "arm",
        "sh", "zsh", "shell", "shellsession", "pascal", "vb", "visualbasic", "golang", "rb", "kt", "rs", "hs", "clj", "jl",
        "ex", "f90", "octave", "mysql", "postgresql", "cbl", "scratchblocks", "yml", "toml", "html", "svg", "plist", "md",
        "text", "docker", "ps1", "make", "Python", "JavaScript", " Swift ",
    ]

    @Test func knowsEveryLanguageOfTheList() {
        for language in Self.languages {
            #expect(CodeHighlighter.supports(language), "\(language) has no grammar")
        }
    }

    @Test func resolvesFenceAliases() {
        for alias in Self.aliases {
            #expect(CodeHighlighter.supports(alias), "\(alias) resolves to nothing")
        }
    }

    /// highlight.js's markdown grammar is quadratic in the length of a line of unmatched `[` (one line
    /// of 32,000 took 10.8 s, and JavaScriptCore cannot interrupt it): a block with a line over the
    /// limit, or longer than the size limit, stays plain code.
    @Test func boundsTheWorkPerBlock() {
        var plain = false
        let elapsed = ContinuousClock().measure {
            plain = CodeHighlighter.html(for: String(repeating: "[", count: 5_000), language: "markdown") == nil
        }
        #expect(plain)
        #expect(elapsed < .milliseconds(100))
        let long = Array(repeating: "let x = 1", count: 10_000).joined(separator: "\n")
        #expect(CodeHighlighter.html(for: long, language: "swift") == nil)
        #expect(CodeHighlighter.html(for: "let x = 1", language: "swift")?.contains("hljs-keyword") == true)
    }

    /// A page highlights a bounded amount of code; the blocks after it stay as cmark wrote them.
    @Test func boundsTheCodeHighlightedPerPage() {
        let block = "<pre><code class=\"language-swift\">let x = 1\n</code></pre>\n"
        let html = CodeHighlighter.render(block + block + block, budget: 20)
        #expect(html.components(separatedBy: "hljs-keyword").count - 1 == 2)
    }

    /// The editor asks on the main thread: `supports` and `tokens` answer while a page render is busy
    /// with a slow block, instead of waiting for the engine that render holds.
    @Test func theEditorDoesNotWaitForThePage() async throws {
        _ = CodeHighlighter.supports("swift")
        _ = CodeHighlighter.tokens(in: "let a = 0", language: "swift")
        _ = CodeHighlighter.html(for: "let a = 0", language: "swift")
        let slow = Array(repeating: String(repeating: "[", count: 1_000), count: 60).joined(separator: "\n")
        let busy = Task.detached {
            ContinuousClock().measure { _ = CodeHighlighter.render("<pre><code class=\"language-markdown\">\(slow)</code></pre>") }
        }
        try await Task.sleep(for: .milliseconds(50))
        let elapsed = ContinuousClock().measure {
            _ = CodeHighlighter.supports("kotlin")
            _ = CodeHighlighter.tokens(in: "fun b() = 1 // \(UUID())", language: "kotlin")
        }
        let rendering = await busy.value
        #expect(rendering > .milliseconds(300), "the page render was not slow enough to test this: \(rendering)")
        #expect(elapsed < .milliseconds(150), "the editor waited \(elapsed)")
    }

    @Test func ignoresUnknownLanguages() {
        for name in ["mermaid", "math", "nope", "", "language-swift"] {
            #expect(!CodeHighlighter.supports(name), "\(name) should stay plain")
            #expect(CodeHighlighter.html(for: "x", language: name) == nil)
            #expect(CodeHighlighter.tokens(in: "x", language: name).isEmpty)
        }
        let html = "<pre><code class=\"language-mermaid\">graph TD\n</code></pre>\n<pre><code>plain\n</code></pre>"
        #expect(CodeHighlighter.render(html) == html)
    }

    @Test func highlightsAFenceInPlace() {
        let html = MarkdownRenderer().renderBody("```swift\nlet x = 1 // hi\n```")
        #expect(html == "<pre><code class=\"language-swift\"><span class=\"hljs-keyword\">let</span> x <span class=\"hljs-operator\">=</span> <span class=\"hljs-number\">1</span> <span class=\"hljs-comment\">// hi</span>\n</code></pre>\n")
    }

    @Test func keepsCmarkEscaping() {
        let html = MarkdownRenderer().renderBody("```html\n<b>a &amp; b</b>\n```")
        #expect(html.contains("&lt;<span class=\"hljs-name\">b</span>&gt;"))
        #expect(html.contains("&amp;amp;") && !html.contains("&amp; b"))
        #expect(!html.contains("<b>"))
    }

    @Test func splitsSpansAtLineBreaks() {
        #expect(CodeHighlighter.balanced("<span class=\"a\">x\ny</span>\nz") == "<span class=\"a\">x</span>\n<span class=\"a\">y</span>\nz")
        #expect(CodeHighlighter.balanced("<span class=\"a\">x<span class=\"b\">\n</span>y</span>") == "<span class=\"a\">x</span>\n<span class=\"a\">y</span>")
        let html = MarkdownRenderer().renderBody("```c\n/* a\n b */\n```", sourcePositions: true)
        #expect(html.contains("<span class=\"line\" data-line=\"2\"><span class=\"hljs-comment\">/* a</span></span>\n<span class=\"line\" data-line=\"3\"><span class=\"hljs-comment\"> b */</span></span>"))
    }

    @Test func tokensCarryUTF16RangesWithinLines() {
        #expect(CodeHighlighter.tokens(in: "let x = 1 // hi", language: "swift") == [
            .init(range: NSRange(location: 0, length: 3), scope: .keyword),
            .init(range: NSRange(location: 8, length: 1), scope: .number),
            .init(range: NSRange(location: 10, length: 5), scope: .comment),
        ])
        #expect(CodeHighlighter.tokens(in: "/* a\n b */", language: "c") == [
            .init(range: NSRange(location: 0, length: 4), scope: .comment),
            .init(range: NSRange(location: 5, length: 5), scope: .comment),
        ])
        // Entities and non-ASCII text keep the offsets of the source.
        let tokens = CodeHighlighter.tokens(in: "if a < b && c { \"é😀\" }", language: "swift")
        #expect(tokens.contains(.init(range: NSRange(location: 0, length: 2), scope: .keyword)))
        #expect(tokens.contains(.init(range: NSRange(location: 16, length: 5), scope: .string)))
    }

    @Test func mapsClassesToScopes() {
        #expect(CodeHighlighter.scope(forClasses: "hljs-keyword") == .keyword)
        #expect(CodeHighlighter.scope(forClasses: "hljs-title class_") == .type)
        #expect(CodeHighlighter.scope(forClasses: "hljs-title function_") == .function)
        #expect(CodeHighlighter.scope(forClasses: "hljs-char escape_") == .string)
        #expect(CodeHighlighter.scope(forClasses: "hljs-meta prompt_") == .meta)
        #expect(CodeHighlighter.scope(forClasses: "hljs-subst") == nil)
        #expect(CodeHighlighter.scope(forClasses: "hljs-tag") == nil)
        #expect(CodeHighlighter.scope(forClasses: "hljs-punctuation") == nil)
        for scope in CodeHighlighter.Scope.allCases {
            #expect(Stylesheet.base.contains("var(--code-\(scope.rawValue))"), "\(scope) has no rule")
        }
    }

    @Test func everyLanguageProducesTokens() {
        let samples: [String: String] = [
            "scratch": "when flag clicked\nforever\n  move (10) steps\n  if <touching [edge v]?> then\n    turn cw (15) degrees\n  end\nend",
            "basic": "10 PRINT \"HELLO\"\n20 GOTO 10", "python": "def f(x):\n    return x + 1  # one", "cobol": "IDENTIFICATION DIVISION.\nPROGRAM-ID. HELLO.\nDISPLAY \"Hi\".",
            "fortran": "program hello\n  print *, 'Hello'\nend program hello", "prolog": "parent(tom, bob).\nX :- Y.", "x86asm": "mov eax, 1\nint 0x80",
            "matlab": "x = linspace(0, 1); % comment", "delphi": "program Hello;\nbegin\n  WriteLn('Hi');\nend.", "elm": "main = text \"Hello\"",
            "vbnet": "Dim x As Integer = 1", "shell": "echo $HOME | grep x", "console": "$ ls -la\ntotal 0", "diff": "- old\n+ new",
        ]
        for (language, code) in samples {
            #expect(!CodeHighlighter.tokens(in: code, language: language).isEmpty, "\(language) produced no token")
        }
    }
}
