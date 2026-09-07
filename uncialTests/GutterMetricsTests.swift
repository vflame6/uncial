import Foundation
import Testing
@testable import Uncial

@Suite struct GutterMetricsTests {
    @Test func keepsThreeDigitsForShortDocuments() {
        #expect(GutterMetrics(lineCount: 0, digitWidth: 8).digits == 3)
        #expect(GutterMetrics(lineCount: 999, digitWidth: 8).digits == 3)
    }

    @Test func growsWithTheLineCount() {
        #expect(GutterMetrics(lineCount: 1000, digitWidth: 8).digits == 4)
        #expect(GutterMetrics(lineCount: 123_456, digitWidth: 8).digits == 6)
    }

    @Test func thicknessAddsPaddingOnBothSides() {
        #expect(GutterMetrics(lineCount: 10, digitWidth: 7.5).thickness == 35)
        #expect(GutterMetrics(lineCount: 5000, digitWidth: 8).thickness == 44)
    }
}
