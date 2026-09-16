import AppKit

/// Side-by-side panes with a divider the app controls. `HSplitView` sized a newly shown pane from its
/// ideal width and left Split View lopsided; here entering the two-pane state puts the divider at
/// `ratio` and a drag then lasts until a pane is hidden again. A hidden pane leaves the split view
/// (a merely hidden subview keeps its divider), so a single visible pane fills the width.
final class PaneSplitView: NSSplitView, NSSplitViewDelegate {
    let leading: NSView
    let trailing: NSView
    var minimumPaneWidth: CGFloat = 280
    private var ratio = SplitLayout.defaultRatio
    private var ratioIsPending = false

    init(leading: NSView, trailing: NSView) {
        self.leading = leading
        self.trailing = trailing
        super.init(frame: .zero)
        isVertical = true
        dividerStyle = .thin
        addArrangedSubview(leading)
        addArrangedSubview(trailing)
        delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("PaneSplitView does not support NSCoder")
    }

    /// Shows the panes asked for; with both visible, the divider goes to `ratio` when the second pane
    /// appears or when the ratio changes, as soon as the width is known.
    func show(leading showsLeading: Bool, trailing showsTrailing: Bool, ratio: Double) {
        let wasSplit = arrangedSubviews.count == 2
        set(leading, shown: showsLeading)
        set(trailing, shown: showsTrailing)
        if showsLeading, showsTrailing, !wasSplit || ratio != self.ratio {
            ratioIsPending = true
        }
        self.ratio = ratio
        adjustSubviews()
        applyPendingRatio()
    }

    /// Adds or removes a pane; `leading` always comes first.
    private func set(_ pane: NSView, shown: Bool) {
        if shown, pane.superview == nil {
            insertArrangedSubview(pane, at: pane === leading ? 0 : arrangedSubviews.count)
        } else if !shown, pane.superview != nil {
            removeArrangedSubview(pane)
            pane.removeFromSuperview()
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        applyPendingRatio()
    }

    private func applyPendingRatio() {
        guard ratioIsPending, bounds.width > 0, arrangedSubviews.count == 2 else { return }
        ratioIsPending = false
        let position = SplitLayout.dividerPosition(width: bounds.width, ratio: ratio, minimum: minimumPaneWidth, divider: dividerThickness)
        setPosition(position, ofDividerAt: 0)
    }

    // MARK: NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(proposedMinimumPosition, minimumPaneWidth)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(proposedMaximumPosition, splitView.bounds.width - dividerThickness - minimumPaneWidth)
    }
}
