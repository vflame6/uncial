import Foundation
import Testing
@testable import Uncial

@MainActor
@Suite struct ScrollSyncControllerTests {
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private func make() -> (ScrollSyncController, Clock) {
        let clock = Clock()
        let controller = ScrollSyncController(now: { clock.now })
        controller.isEnabled = true
        return (controller, clock)
    }

    @Test func disabledControllerRecordsButDoesNotTarget() {
        let controller = ScrollSyncController()
        controller.editorDidScroll(toLine: 5)
        #expect(controller.previewTarget == nil)
        #expect(controller.lastEditorLine == 5)
        controller.previewDidScroll(toLine: 7)
        #expect(controller.editorTarget == nil)
    }

    @Test func editorDrivesPreviewAndSuppressesEcho() {
        let (controller, clock) = make()
        controller.editorDidScroll(toLine: 5)
        let first = controller.previewTarget
        #expect(first?.line == 5)
        controller.previewDidScroll(toLine: 5.2)
        #expect(controller.editorTarget == nil)
        clock.advance(0.31)
        controller.previewDidScroll(toLine: 7)
        #expect(controller.editorTarget?.line == 7)
        #expect(controller.lastEditorLine == 7)
        controller.editorDidScroll(toLine: 7.1)
        #expect(controller.previewTarget == nil)
        clock.advance(0.31)
        controller.editorDidScroll(toLine: 9)
        #expect(controller.previewTarget?.line == 9)
        #expect((controller.previewTarget?.token ?? 0) > (first?.token ?? 0))
    }

    @Test func resyncReissuesLastEditorLine() {
        let (controller, clock) = make()
        controller.editorDidScroll(toLine: 5)
        let token = controller.previewTarget?.token ?? 0
        clock.advance(1)
        controller.resyncPreview()
        #expect(controller.previewTarget?.line == 5)
        #expect((controller.previewTarget?.token ?? 0) > token)
    }

    /// Once the preview drives, or sync is off (Read Only), the preview has no target left: the web
    /// view re-applies its last target after every body swap and reload, which used to throw the
    /// reader back to where the editor once was.
    @Test func forgetsThePreviewTargetWhenThePreviewDrivesOrSyncStops() {
        let (controller, clock) = make()
        controller.editorDidScroll(toLine: 5)
        #expect(controller.previewTarget?.line == 5)
        clock.advance(0.31)
        controller.previewDidScroll(toLine: 40)
        #expect(controller.previewTarget == nil)
        clock.advance(0.31)
        controller.editorDidScroll(toLine: 8)
        #expect(controller.previewTarget?.line == 8)
        controller.isEnabled = false
        #expect(controller.previewTarget == nil)
    }

    @Test func enablingResyncsFromTheRecordedLine() {
        let controller = ScrollSyncController()
        controller.editorDidScroll(toLine: 12)
        controller.isEnabled = true
        #expect(controller.previewTarget?.line == 12)
    }
}
