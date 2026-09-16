import AppKit
import Testing
@testable import Uncial

@MainActor
@Suite struct PaneSplitViewTests {
    private func panes(width: CGFloat = 1000, ratio: Double = 0.5) -> PaneSplitView {
        let view = PaneSplitView(leading: NSView(), trailing: NSView())
        view.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        view.show(leading: true, trailing: true, ratio: ratio)
        return view
    }

    @Test func entersTheTwoPaneStateAtTheRatio() {
        let half = panes()
        #expect(half.leading.frame.width == 500)
        #expect(half.trailing.frame.width == 499)
        #expect(half.trailing.frame.minX == 501)
        let third = panes(ratio: 0.3)
        #expect(third.leading.frame.width == 300)
        #expect(third.trailing.frame.width == 699)
    }

    @Test func aSinglePaneFillsTheWidth() {
        let view = panes()
        view.show(leading: true, trailing: false, ratio: 0.5)
        #expect(view.leading.frame.width == 1000)
        #expect(view.trailing.superview == nil)
        view.show(leading: false, trailing: true, ratio: 0.5)
        #expect(view.trailing.frame.width == 1000)
        #expect(view.leading.superview == nil)
    }

    @Test func keepsADragUntilAPaneIsHidden() {
        let view = panes()
        view.setPosition(700, ofDividerAt: 0)
        view.show(leading: true, trailing: true, ratio: 0.5)
        #expect(view.leading.frame.width == 700)
        view.show(leading: true, trailing: false, ratio: 0.5)
        view.show(leading: true, trailing: true, ratio: 0.5)
        #expect(view.leading.frame.width == 500)
    }

    @Test func appliesANewRatioWhileBothAreVisible() {
        let view = panes()
        view.show(leading: true, trailing: true, ratio: 0.3)
        #expect(view.leading.frame.width == 300)
    }

    @Test func appliesTheRatioOnceTheWidthIsKnown() {
        let view = PaneSplitView(leading: NSView(), trailing: NSView())
        view.show(leading: true, trailing: true, ratio: 0.3)
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 400)
        #expect(view.leading.frame.width == 300)
        #expect(view.trailing.frame.width == 699)
    }

    @Test func keepsTheProportionWhenResized() {
        let view = panes(ratio: 0.3)
        view.setFrameSize(NSSize(width: 1400, height: 400))
        #expect(abs(view.leading.frame.width - 420) <= 1)
        #expect(abs(view.leading.frame.width + view.trailing.frame.width - 1399) < 0.01)
    }

    @Test func enforcesTheMinimumPaneWidth() {
        let view = panes(ratio: 0.2)
        #expect(view.leading.frame.width == 280)
        view.show(leading: true, trailing: true, ratio: 0.8)
        #expect(view.trailing.frame.width == 280)
    }
}
