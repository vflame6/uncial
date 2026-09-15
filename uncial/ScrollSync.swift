import Foundation
import Observation

/// One programmatic scroll request. A new `token` means "do it again", even for the same line.
struct ScrollTarget: Equatable {
    let line: Double
    let token: Int
}

/// Keeps the editor and the preview at the same place in Split View.
///
/// Lines are 1-based document lines with a fraction (12.4 = 40 % into line 12), the unit cmark's
/// `data-sourcepos` uses. Whichever pane the user scrolls drives the other; the driven pane's
/// echo is ignored for a short window so the two never ping-pong.
@Observable
final class ScrollSyncController {
    static let suppression: TimeInterval = 0.3

    var isEnabled = false {
        didSet { if isEnabled, !oldValue { resyncPreview() } }
    }

    private(set) var editorTarget: ScrollTarget?
    private(set) var previewTarget: ScrollTarget?
    private(set) var lastEditorLine: Double = 1

    private let now: () -> Date
    private var suppressEditorUntil = Date.distantPast
    private var suppressPreviewUntil = Date.distantPast
    private var token = 0

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func editorDidScroll(toLine line: Double) {
        lastEditorLine = line
        guard isEnabled, now() >= suppressEditorUntil else { return }
        token += 1
        previewTarget = ScrollTarget(line: line, token: token)
        suppressPreviewUntil = now().addingTimeInterval(Self.suppression)
    }

    func previewDidScroll(toLine line: Double) {
        guard isEnabled, now() >= suppressPreviewUntil else { return }
        lastEditorLine = line
        token += 1
        editorTarget = ScrollTarget(line: line, token: token)
        suppressEditorUntil = now().addingTimeInterval(Self.suppression)
    }

    /// Puts the preview back where the editor is, e.g. after the rendered body was replaced.
    func resyncPreview() {
        guard isEnabled else { return }
        token += 1
        previewTarget = ScrollTarget(line: lastEditorLine, token: token)
        suppressPreviewUntil = now().addingTimeInterval(Self.suppression)
    }
}
