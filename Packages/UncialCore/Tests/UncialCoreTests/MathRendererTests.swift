import Testing
@testable import UncialCore

@Suite struct MathRendererTests {
    @Test func rendersInlineAndDisplayMathAsMathML() {
        let html = "<p>Euler: $e^{i\\pi} + 1 = 0$ and $$\\int_0^1 x^2\\,dx$$</p>"
        let output = MathRenderer.render(html)
        #expect(output.contains("<math"))
        #expect(output.contains("<annotation encoding=\"application/x-tex\">e^{i\\pi} + 1 = 0</annotation>"))
        #expect(output.contains("display=\"block\""))
        #expect(!output.contains("$e^"))
    }

    @Test func leavesCodeAndPricesAlone() {
        let html = "<p>costs $5 and $10 today; <code>$x$</code></p>\n<pre><code>$$y$$</code></pre>"
        #expect(MathRenderer.render(html) == html)
    }

    @Test func rendersMathFencesAsDisplayMath() {
        let html = "<pre data-sourcepos=\"3:1-5:3\"><code class=\"language-math\">a &lt; b\n</code></pre>"
        let output = MathRenderer.render(html)
        #expect(output.hasPrefix("<p class=\"math\" data-sourcepos=\"3:1-5:3\"><span class=\"katex\"><math"))
        #expect(output.contains("<annotation encoding=\"application/x-tex\">a &lt; b</annotation>"))
        #expect(!output.contains("<pre"))
    }

    @Test func rendersOneFormulaForTheEditor() {
        #expect(MathRenderer.mathML("x^2", display: false).hasPrefix("<span class=\"katex\"><math"))
        #expect(MathRenderer.mathML("x^2", display: true).contains("display=\"block\""))
        #expect(MathRenderer.mathML("\\frac{1}", display: false).contains("katex-error"))
    }

    @Test func keepsBrokenMathReadable() {
        let output = MathRenderer.render("<p>$\\frac{1}$</p>")
        #expect(output.contains("katex-error") && output.contains("\\frac{1}"))
    }
}
