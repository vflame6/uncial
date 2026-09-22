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
