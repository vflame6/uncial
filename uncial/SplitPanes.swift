import AppKit
import SwiftUI

/// `PaneSplitView` for SwiftUI content. A hidden pane renders nothing, so the editor and the preview
/// come and go with the mode exactly as they did as `HSplitView` children.
struct SplitPanes<Leading: View, Trailing: View>: NSViewRepresentable {
    var showsLeading: Bool
    var showsTrailing: Bool
    var ratio: Double
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    func makeCoordinator() -> Coordinator {
        Coordinator(
            leading: NSHostingView(rootView: Pane(isShown: showsLeading, content: leading())),
            trailing: NSHostingView(rootView: Pane(isShown: showsTrailing, content: trailing()))
        )
    }

    func makeNSView(context: Context) -> PaneSplitView {
        PaneSplitView(leading: context.coordinator.leading, trailing: context.coordinator.trailing)
    }

    func updateNSView(_ view: PaneSplitView, context: Context) {
        context.coordinator.leading.rootView = Pane(isShown: showsLeading, content: leading())
        context.coordinator.trailing.rootView = Pane(isShown: showsTrailing, content: trailing())
        view.show(leading: showsLeading, trailing: showsTrailing, ratio: ratio)
    }

    final class Coordinator {
        let leading: NSHostingView<Pane<Leading>>
        let trailing: NSHostingView<Pane<Trailing>>

        init(leading: NSHostingView<Pane<Leading>>, trailing: NSHostingView<Pane<Trailing>>) {
            self.leading = leading
            self.trailing = trailing
            // The split view owns the sizes; no SwiftUI size constraints on the panes.
            leading.sizingOptions = []
            trailing.sizingOptions = []
        }
    }

    struct Pane<Content: View>: View {
        let isShown: Bool
        let content: Content

        var body: some View {
            if isShown {
                content
            }
        }
    }
}
