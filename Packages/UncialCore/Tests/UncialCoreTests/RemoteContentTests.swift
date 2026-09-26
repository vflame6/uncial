import Testing
@testable import UncialCore

@Suite struct RemoteContentTests {
    @Test func blocksWebResourcesOnMediaElements() {
        #expect(RemoteContent.block(in: #"<img src="https://x.test/a.png" alt="a">"#) == #"<img data-blocked-src="https://x.test/a.png" alt="a">"#)
        #expect(RemoteContent.block(in: #"<IMG SRC='HTTP://x.test/a.png'>"#) == #"<IMG data-blocked-SRC='HTTP://x.test/a.png'>"#)
        #expect(RemoteContent.block(in: #"<img src=//x.test/a.png>"#) == #"<img data-blocked-src=//x.test/a.png>"#)
        #expect(RemoteContent.block(in: #"<video poster="https://x.test/p.jpg"><source src="https://x.test/v.mp4"></video>"#)
                == #"<video data-blocked-poster="https://x.test/p.jpg"><source data-blocked-src="https://x.test/v.mp4"></video>"#)
        #expect(RemoteContent.block(in: #"<object data="https://x.test/o.swf"></object><link href="https://x.test/s.css" rel="stylesheet">"#)
                == #"<object data-blocked-data="https://x.test/o.swf"></object><link data-blocked-href="https://x.test/s.css" rel="stylesheet">"#)
        #expect(RemoteContent.block(in: #"<svg><image xlink:href="https://x.test/i.svg"/><use href="https://x.test/d.svg#a"/></svg>"#)
                == #"<svg><image data-blocked-xlink:href="https://x.test/i.svg"/><use data-blocked-href="https://x.test/d.svg#a"/></svg>"#)
    }

    @Test func blocksASrcsetWithAnyWebCandidate() {
        #expect(RemoteContent.block(in: #"<img srcset="a.png 1x, https://x.test/a2.png 2x" src="a.png">"#)
                == #"<img data-blocked-srcset="a.png 1x, https://x.test/a2.png 2x" src="a.png">"#)
    }

    @Test func leavesLocalAndInlineContentAndLinks() {
        for html in [
            #"<img src="a.png"><img src="data:image/png;base64,AAAA"><img src="/abs/a.png">"#,
            #"<a href="https://x.test">x</a> <a href="//x.test">y</a>"#,
            #"<p>see &lt;img src="https://x.test/a.png"&gt;</p>"#,
            #"<pre><code>&lt;link href="https://x.test"&gt;</code></pre>"#,
            #"<img src="httpbin.png">"#,
        ] {
            #expect(RemoteContent.block(in: html) == html, "\(html)")
        }
    }

    @Test func disarmsStyleURLsAndMetaRefresh() {
        #expect(RemoteContent.block(in: #"<div style="background: url(https://x.test/b.png) no-repeat; color: red">"#)
                == #"<div style="background: none no-repeat; color: red">"#)
        #expect(RemoteContent.block(in: #"<div style="background:url( '//x.test/b.png' )">"#) == #"<div style="background:none">"#)
        #expect(RemoteContent.block(in: #"<div style="background: url(local.png)">"#) == #"<div style="background: url(local.png)">"#)
        #expect(RemoteContent.block(in: #"<meta http-equiv="refresh" content="0;url=https://x.test">"#)
                == #"<meta data-blocked-http-equiv="refresh" content="0;url=https://x.test">"#)
    }

    /// Each of these reached the network from Quick Look: presentational `background`, an SVG
    /// filter image, a base URL, SMIL setting an `href`, and spellings of a URL the browser accepts
    /// (character references, controls, tabs and newlines inside it, backslashes, no gap before the
    /// attribute).
    @Test func blocksTheSpellingsBrowsersAccept() {
        let cases: [(String, String)] = [
            (#"<table background="http://x.test/t.png"><tr><td background="https://x.test/c.png">x</td></tr></table>"#,
             #"<table data-blocked-background="http://x.test/t.png"><tr><td data-blocked-background="https://x.test/c.png">x</td></tr></table>"#),
            (#"<svg><filter id="f"><feImage href="http://x.test/f.png"/></filter></svg>"#,
             #"<svg><filter id="f"><feImage data-blocked-href="http://x.test/f.png"/></filter></svg>"#),
            (#"<base href="http://x.test/">"#, #"<base data-blocked-href="http://x.test/">"#),
            (#"<img src="&#104;ttp://x.test/e.png">"#, #"<img data-blocked-src="&#104;ttp://x.test/e.png">"#),
            (#"<img src="&#x68;ttps://x.test/h.png">"#, #"<img data-blocked-src="&#x68;ttps://x.test/h.png">"#),
            (#"<img src="https&colon;//x.test/n.png">"#, #"<img data-blocked-src="https&colon;//x.test/n.png">"#),
            (#"<img/src="http://x.test/s.png">"#, #"<img/data-blocked-src="http://x.test/s.png">"#),
            (#"<img alt="a"src="http://x.test/g.png">"#, #"<img alt="a"data-blocked-src="http://x.test/g.png">"#),
            (#"<img src="&#1;http://x.test/c.png">"#, #"<img data-blocked-src="&#1;http://x.test/c.png">"#),
            (#"<img src="ht&#9;tp://x.test/t.png">"#, #"<img data-blocked-src="ht&#9;tp://x.test/t.png">"#),
            ("<img src=\"ht\ntp://x.test/l.png\">", "<img data-blocked-src=\"ht\ntp://x.test/l.png\">"),
            (#"<img src="\\x.test/b.png">"#, #"<img data-blocked-src="\\x.test/b.png">"#),
            (#"<svg><image><set attributeName="href" to="http://x.test/set.png"/></image></svg>"#,
             #"<svg><image><set attributeName="href" data-blocked-to="http://x.test/set.png"/></image></svg>"#),
            (#"<svg><image><animate attributeName="href" values="a.png;http://x.test/v.png"/></image></svg>"#,
             #"<svg><image><animate attributeName="href" data-blocked-values="a.png;http://x.test/v.png"/></image></svg>"#),
            (#"<meta/http-equiv="refresh" content="0;url=https://x.test">"#, #"<meta/data-blocked-http-equiv="refresh" content="0;url=https://x.test">"#),
        ]
        for (html, blocked) in cases {
            #expect(RemoteContent.block(in: html) == blocked)
        }
    }

    /// A style whose web URL hides behind a CSS escape, a character reference or `image-set()`'s
    /// plain strings loses the whole attribute.
    @Test func blocksWebURLsHiddenInStyles() {
        let cases: [(String, String)] = [
            (#"<div style="background-image: image-set('http://x.test/i.png' 1x)">"#,
             #"<div data-blocked-style="background-image: image-set('http://x.test/i.png' 1x)">"#),
            (#"<div style="background: url(ht\74p://x.test/e.png)">"#, #"<div data-blocked-style="background: url(ht\74p://x.test/e.png)">"#),
            (#"<div style="background: url(&#104;ttp://x.test/r.png)">"#, #"<div data-blocked-style="background: url(&#104;ttp://x.test/r.png)">"#),
            (#"<div style="background: url(local.png); color: red">"#, #"<div style="background: url(local.png); color: red">"#),
        ]
        for (html, blocked) in cases {
            #expect(RemoteContent.block(in: html) == blocked)
        }
    }

    /// Quick Look has no content rule list: with remote content off its page carries a policy that
    /// allows no load from the web at all, whatever the HTML says.
    @Test func offlineDocumentsCarryAContentSecurityPolicy() {
        let renderer = MarkdownRenderer()
        let offline = renderer.renderDocument("# T", title: "t")
        #expect(offline.contains(#"<meta http-equiv="Content-Security-Policy" content="\#(HTMLDocument.offlinePolicy)">"#))
        #expect(HTMLDocument.offlinePolicy.contains("default-src 'none'") && HTMLDocument.offlinePolicy.contains("base-uri 'none'"))
        #expect(!renderer.renderDocument("# T", title: "t", remoteContent: true).contains("Content-Security-Policy"))
        #expect(!HTMLDocument.wrap(body: "", title: "t").contains("Content-Security-Policy"))
    }

    @Test func rendererAppliesItUnlessAllowed() {
        let renderer = MarkdownRenderer()
        let markdown = "![a](https://x.test/a.png) [l](https://x.test)"
        let blocked = renderer.renderBody(markdown)
        #expect(blocked.contains(#"<img data-blocked-src="https://x.test/a.png" alt="a" />"#))
        #expect(blocked.contains(#"<a href="https://x.test">l</a>"#))
        #expect(renderer.renderBody(markdown, remoteContent: true).contains(#"<img src="https://x.test/a.png" alt="a" />"#))
        #expect(renderer.renderDocument(markdown, title: "t", remoteContent: true).contains(#"<img src="https://x.test/a.png""#))
        #expect(renderer.renderDocument(markdown, title: "t").contains("data-blocked-src"))
    }
}
