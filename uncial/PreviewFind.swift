import AppKit
import Observation
import WebKit

/// Lets the find bar and menu commands reach the preview's web view.
final class PreviewHandle {
    weak var webView: WKWebView?

    /// Selects and scrolls to the next (or previous) case-insensitive match, wrapping around.
    func find(_ query: String, backwards: Bool) {
        guard let webView, !query.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(query, configuration: configuration) { _ in }
    }

    func count(_ query: String, completion: @escaping (Int) -> Void) {
        guard let webView, !query.isEmpty else {
            completion(0)
            return
        }
        webView.evaluateJavaScript(PreviewScripts.countMatches(query)) { value, _ in
            completion(value as? Int ?? 0)
        }
    }

    func selectedText(completion: @escaping (String) -> Void) {
        guard let webView else {
            completion("")
            return
        }
        webView.evaluateJavaScript(PreviewScripts.selectedText) { value, _ in
            completion(value as? String ?? "")
        }
    }
}

/// State of the rendered page's find bar (Read Only mode). `WKWebView.find` selects and scrolls to
/// matches; the count comes from the page's visible text. WKWebView is not an `NSTextFinderClient`,
/// so the text view's bar cannot be reused.
@Observable
final class PreviewFindController {
    let handle = PreviewHandle()
    var isVisible = false
    var query = "" {
        didSet { if query != oldValue { search() } }
    }
    private(set) var matchCount: Int?
    /// Bumped whenever the search field should take focus.
    private(set) var focusRequest = 0

    var status: String? {
        matchCount.map { $0 == 0 ? "Not found" : $0 == 1 ? "1 found" : "\($0) found" }
    }

    func perform(_ action: NSTextFinder.Action) {
        switch action {
        case .showFindInterface, .showReplaceInterface:
            show()
        case .nextMatch:
            if !isVisible { show() }
            find(backwards: false)
        case .previousMatch:
            if !isVisible { show() }
            find(backwards: true)
        case .setSearchString:
            handle.selectedText { [weak self] text in
                if !text.isEmpty { self?.query = text }
            }
        case .hideFindInterface:
            hide()
        default:
            break
        }
    }

    func show() {
        isVisible = true
        focusRequest += 1
    }

    func hide() {
        isVisible = false
    }

    func find(backwards: Bool) {
        handle.find(query, backwards: backwards)
    }

    private func search() {
        guard !query.isEmpty else {
            matchCount = nil
            return
        }
        handle.count(query) { [weak self] count in
            self?.matchCount = count
        }
        handle.find(query, backwards: false)
    }
}
