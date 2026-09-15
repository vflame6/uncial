import Foundation

/// Layout numbers for the inline presentation.
nonisolated enum InlineLayout {
    /// Widest text column in Live Preview, close to the rendered page's content width.
    static let readableWidth: CGFloat = 720

    /// Horizontal inset that centers a column of at most `maxWidth` in a view `viewWidth` wide,
    /// never below `minimum`.
    static func horizontalInset(viewWidth: CGFloat, maxWidth: CGFloat = readableWidth, minimum: CGFloat = 16) -> CGFloat {
        max(minimum, floor((viewWidth - maxWidth) / 2))
    }
}
