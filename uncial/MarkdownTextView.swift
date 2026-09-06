import AppKit
import SwiftUI
import UncialCore

/// Plain-text Markdown editor: SF Mono, soft wrap, no smart substitutions, native find bar and undo.
struct MarkdownTextView: NSViewRepresentable {
    let text: String
    let palette: EditorPalette?
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let textView = ThemedTextView(usingTextLayoutManager: true)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFontPanel = false
        textView.importsGraphics = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.delegate = context.coordinator
        textView.string = text
        textView.palette = palette
        scrollView.documentView = textView
        context.coordinator.textView = textView
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ThemedTextView else { return }
        context.coordinator.onChange = onChange
        if textView.palette != palette {
            textView.palette = palette
        }
        guard textView.string != text else { return }
        // External change (reload, another editor): replace the text, keep the caret in range, drop undo history.
        let selection = textView.selectedRange()
        textView.string = text
        let length = (text as NSString).length
        let location = min(selection.location, length)
        textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        textView.undoManager?.removeAllActions()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void
        weak var textView: ThemedTextView?

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onChange(textView.string)
        }
    }
}

/// NSTextView that colors itself from an `EditorPalette` and follows light/dark switches.
final class ThemedTextView: NSTextView {
    var palette: EditorPalette? {
        didSet { if palette != oldValue { applyPalette() } }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPalette()
    }

    private func applyPalette() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let colors = palette.map { isDark ? $0.dark : $0.light }
        let background = colors.map { NSColor(rgb: $0.background) } ?? .textBackgroundColor
        let foreground = colors.map { NSColor(rgb: $0.foreground) } ?? .textColor
        backgroundColor = background
        textColor = foreground
        insertionPointColor = foreground
        enclosingScrollView?.backgroundColor = background
    }
}

private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
