import Testing
@testable import UncialCore

@Suite struct MermaidRendererTests {
    @Test func rendersFencesAsInlineSVG() {
        let html = "<pre data-sourcepos=\"3:1-6:3\"><code class=\"language-mermaid\">graph LR\n  A[Start] --&gt; B{Done?}\n</code></pre>"
        let output = MermaidRenderer.render(html)
        #expect(output.hasPrefix("<figure class=\"mermaid\" data-sourcepos=\"3:1-6:3\"><svg"))
        #expect(output.hasSuffix("</svg></figure>"))
        #expect(output.contains(">Start<") && output.contains("Done?"))
        #expect(!output.contains("<pre"))
    }

    @Test func diagramsTakeTheirColorsAndFontFromThePage() {
        let output = MermaidRenderer.render("<pre><code class=\"language-mermaid\">sequenceDiagram\n  A-&gt;&gt;B: hi\n</code></pre>")
        #expect(output.contains("--fg:var(--diagram-fg)") && output.contains("--accent:var(--diagram-accent)"))
        #expect(output.contains("text { font-family: var(--font-body); }"))
        #expect(!output.contains("googleapis") && !output.contains("@import"))
        #expect(Stylesheet.base.contains("figure.mermaid { margin: 16px 0; text-align: center; --diagram-bg: var(--bg);"))
    }

    @Test func acceptsSemicolonSeparatedStatements() {
        let output = MermaidRenderer.render("<pre><code class=\"language-mermaid\">graph TD; A--&gt;B;\n</code></pre>")
        #expect(output.hasPrefix("<figure class=\"mermaid\"><svg"))
        #expect(MermaidRenderer.normalized("graph TD; A[\"x; y\"]-->B;") == "graph TD\nA[\"x; y\"]-->B")
        #expect(MermaidRenderer.normalized("graph TD\n  A --> B\n") == "graph TD\n  A --> B")
    }

    @Test func keepsUnsupportedDiagramsAsCode() {
        let html = "<pre><code class=\"language-mermaid\">gantt\n  title A\n</code></pre>"
        #expect(MermaidRenderer.render(html) == html)
    }

    @Test func leavesOtherCodeAlone() {
        let html = "<pre><code class=\"language-swift\">graph TD\n</code></pre><p>mermaid</p>"
        #expect(MermaidRenderer.render(html) == html)
    }

    @Test func escapesLabels() {
        let html = "<pre><code class=\"language-mermaid\">graph LR\n  A[\"&lt;script&gt;alert(1)&lt;/script&gt;\"] --&gt; B\n</code></pre>"
        let output = MermaidRenderer.render(html)
        #expect(output.contains("<svg") && !output.contains("<script>"))
        #expect(output.contains("&lt;script&gt;"))
    }

    @Test func pipelineNumbersTheFigure() {
        let html = MarkdownRenderer().renderBody("Intro\n\n```mermaid\ngraph LR\n  A --> B\n```\n", sourcePositions: true)
        #expect(html.contains("<figure class=\"mermaid\" data-line=\"3\" data-sourcepos=\"3:1-6:3\"><svg"))
        #expect(!html.contains("language-mermaid"))
    }
}
