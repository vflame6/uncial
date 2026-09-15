import CoreGraphics
import Foundation

/// Where windows that open on their own go. AppKit's `center()` and the Open panel's own placement sit
/// well above the middle of the screen; this puts a frame exactly in the middle.
nonisolated enum WindowPlacement {
    /// The frame of `size` centered in `area` (a screen's visible frame), its origin rounded to whole
    /// points. A frame larger than the area keeps its top-left corner inside it, so the title bar and
    /// the close button stay reachable.
    static func centered(_ size: CGSize, in area: CGRect) -> CGRect {
        let x = max((area.midX - size.width / 2).rounded(), area.minX)
        let y = min((area.midY - size.height / 2).rounded(), area.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
