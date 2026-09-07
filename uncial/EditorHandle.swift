import AppKit

/// Lets menu commands reach the editor's text view directly: in Live Preview the responder chain may
/// point at the preview, and `performTextFinderAction` only works on the text view itself.
final class EditorHandle {
    weak var textView: ThemedTextView?

    func performFind(_ action: NSTextFinder.Action) {
        guard let textView, let window = textView.window else { return }
        window.makeFirstResponder(textView)
        let item = NSMenuItem()
        item.tag = action.rawValue
        textView.performTextFinderAction(item)
    }
}
