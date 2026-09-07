import Foundation

/// Width of the line-number gutter for a line count: at least three digits, six points of padding each side.
nonisolated struct GutterMetrics: Equatable {
    static let minimumDigits = 3
    static let padding: CGFloat = 6

    let digits: Int
    let thickness: CGFloat

    init(lineCount: Int, digitWidth: CGFloat) {
        digits = max(Self.minimumDigits, String(max(lineCount, 1)).count)
        thickness = ceil(CGFloat(digits) * digitWidth + 2 * Self.padding)
    }
}
