import CoreGraphics
import Foundation
import Testing
@testable import Uncial

@Suite struct SplitLayoutTests {
    @Test func boundsTheRatio() {
        #expect(SplitLayout.defaultRatio == 0.5)
        #expect(SplitLayout.ratioRange == 0.2...0.8)
        #expect(SplitLayout.ratioStep == 0.05)
        #expect(SplitLayout.clamp(0.5) == 0.5)
        #expect(SplitLayout.clamp(0.05) == 0.2)
        #expect(SplitLayout.clamp(1.5) == 0.8)
        #expect(SplitLayout.clamp(.nan) == 0.5)
    }

    @Test func placesTheDividerByRatioInWholePoints() {
        #expect(SplitLayout.dividerPosition(width: 1000, ratio: 0.5, minimum: 280, divider: 1) == 500)
        #expect(SplitLayout.dividerPosition(width: 1000, ratio: 0.3, minimum: 280, divider: 1) == 300)
        #expect(SplitLayout.dividerPosition(width: 1000, ratio: 0.65, minimum: 280, divider: 1) == 649)
    }

    @Test func keepsBothPanesAtTheirMinimum() {
        #expect(SplitLayout.dividerPosition(width: 1000, ratio: 0.2, minimum: 280, divider: 1) == 280)
        #expect(SplitLayout.dividerPosition(width: 1000, ratio: 0.8, minimum: 280, divider: 1) == 719)
        // Too narrow for two minimums: split what there is evenly.
        #expect(SplitLayout.dividerPosition(width: 400, ratio: 0.8, minimum: 280, divider: 1) == 200)
    }
}
