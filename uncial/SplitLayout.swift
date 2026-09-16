import CoreGraphics
import Foundation

/// Numbers for Split View's divider.
nonisolated enum SplitLayout {
    /// Share of the width the source pane gets when a window enters Split View.
    static let defaultRatio = 0.5
    static let ratioRange = 0.2...0.8
    static let ratioStep = 0.05

    /// `ratio` within `ratioRange`; anything unusable, such as a corrupted default, becomes `defaultRatio`.
    static func clamp(_ ratio: Double) -> Double {
        guard ratio.isFinite else { return defaultRatio }
        return min(max(ratio, ratioRange.lowerBound), ratioRange.upperBound)
    }

    /// Where the divider goes in a split `width` wide: the leading pane gets `ratio` of the room left by
    /// the divider, in whole points, with both panes kept at `minimum` or, when that no longer fits,
    /// half the room each.
    static func dividerPosition(width: CGFloat, ratio: Double, minimum: CGFloat, divider: CGFloat) -> CGFloat {
        let room = width - divider
        guard room >= 2 * minimum else { return (room / 2).rounded() }
        return min(max((room * ratio).rounded(), minimum), room - minimum)
    }
}
