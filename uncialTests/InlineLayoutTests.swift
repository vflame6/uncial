import Foundation
import Testing
@testable import Uncial

@Suite struct InlineLayoutTests {
    @Test func centersTheColumnInWideViews() {
        #expect(InlineLayout.horizontalInset(viewWidth: 1000) == 140)
        #expect(InlineLayout.horizontalInset(viewWidth: 800) == 40)
        #expect(InlineLayout.horizontalInset(viewWidth: 753) == 16)
    }

    @Test func keepsTheMinimumInsetInNarrowViews() {
        #expect(InlineLayout.horizontalInset(viewWidth: 600) == 16)
        #expect(InlineLayout.horizontalInset(viewWidth: 300, maxWidth: 200, minimum: 8) == 50)
    }
}
