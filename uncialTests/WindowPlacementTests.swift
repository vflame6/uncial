import CoreGraphics
import Foundation
import Testing
@testable import Uncial

@Suite struct WindowPlacementTests {
    /// A 3440 × 1440 display below its menu bar.
    let screen = CGRect(x: 0, y: 0, width: 3440, height: 1409)

    @Test func centersTheFrameInTheArea() {
        let frame = WindowPlacement.centered(CGSize(width: 880, height: 448), in: screen)
        #expect(frame == CGRect(x: 1280, y: 481, width: 880, height: 448))
    }

    @Test func honorsTheAreaOrigin() {
        let area = CGRect(x: 3440, y: 100, width: 1440, height: 800)
        let frame = WindowPlacement.centered(CGSize(width: 520, height: 672), in: area)
        #expect(frame == CGRect(x: 3900, y: 164, width: 520, height: 672))
    }

    @Test func roundsTheOriginToWholePoints() {
        let frame = WindowPlacement.centered(CGSize(width: 521, height: 672), in: screen)
        #expect(frame.origin == CGPoint(x: 1460, y: 369))
        #expect(frame.size == CGSize(width: 521, height: 672))
    }

    @Test func keepsTheTopLeftInsideAnAreaThatIsTooSmall() {
        let frame = WindowPlacement.centered(CGSize(width: 1000, height: 900), in: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(frame.minX == 0)
        #expect(frame.maxY == 600)
        #expect(frame.size == CGSize(width: 1000, height: 900))
    }
}
