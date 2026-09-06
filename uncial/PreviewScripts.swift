/// The app-authored JavaScript the preview runs. Page scripts stay disabled; these are injected
/// through `WKUserScript` / `evaluateJavaScript` and only read layout to keep scrolling in sync.
nonisolated enum PreviewScripts {
    static let messageHandlerName = "uncialScroll"

    /// Reports the 1-based source line at the top of the viewport whenever the page scrolls.
    /// Throttled with `setTimeout`, not `requestAnimationFrame`: animation frames stop for a
    /// window that is not frontmost, timers do not.
    static let observer = #"""
    (function () {
      if (window.__uncialObserver) { return; }
      window.__uncialObserver = true;
      var ticking = false;
      function report() {
        ticking = false;
        var best = null;
        var bestTop = -Infinity;
        var elements = document.querySelectorAll('[data-sourcepos]');
        for (var i = 0; i < elements.length; i++) {
          var m = /^(\d+):\d+-(\d+):\d+$/.exec(elements[i].getAttribute('data-sourcepos'));
          if (!m) { continue; }
          var r = elements[i].getBoundingClientRect();
          if (r.height <= 0) { continue; }
          if (r.top <= 1 && r.top > bestTop) {
            best = { s: +m[1], t: +m[2], top: r.top, h: r.height };
            bestTop = r.top;
          }
        }
        var line = 1;
        if (best) {
          var span = best.t - best.s + 1;
          var frac = Math.min(Math.max(-best.top / best.h, 0), 1);
          line = best.s + frac * span;
        }
        window.webkit.messageHandlers.uncialScroll.postMessage({ line: line, y: window.scrollY });
      }
      window.addEventListener('scroll', function () {
        if (!ticking) { ticking = true; setTimeout(report, 40); }
      }, { passive: true });
    })();
    """#

    /// Scrolls so the block containing the fractional 1-based `line` sits at the top edge.
    static func scrollToLine(_ line: Double) -> String {
        #"""
        (function (line) {
          var best = null;
          var elements = document.querySelectorAll('[data-sourcepos]');
          for (var i = 0; i < elements.length; i++) {
            var m = /^(\d+):\d+-(\d+):\d+$/.exec(elements[i].getAttribute('data-sourcepos'));
            if (!m) { continue; }
            var s = +m[1];
            if (s <= line && (!best || s >= best.s)) { best = { e: elements[i], s: s, t: +m[2] }; }
          }
          if (!best) { window.scrollTo(0, 0); return; }
          var r = best.e.getBoundingClientRect();
          var span = best.t - best.s + 1;
          var frac = Math.min(Math.max((line - best.s) / span, 0), 1);
          window.scrollTo(0, r.top + window.scrollY + frac * r.height);
        })(\#(line));
        """#
    }
}
