import Foundation
import Testing
@testable import Uncial

@Suite final class DocumentWindowFramesTests {
    private let suites = PreferenceSuites()
    private let notes = URL(fileURLWithPath: "/notes/a.md")
    private let todo = URL(fileURLWithPath: "/notes/todo.md")

    deinit {
        suites.removeAll()
    }

    /// A document's window opens where that document was; one never open here, where the last window was.
    @Test func remembersEachDocumentAndTheLastWindow() {
        let frames = DocumentWindowFrames(defaults: suites.make())
        #expect(frames.frame(for: notes) == nil)
        frames.remember("10 20 800 600 0 0 1440 900 ", for: notes)
        #expect(frames.frame(for: notes) == "10 20 800 600 0 0 1440 900 ")
        #expect(frames.frame(for: todo) == "10 20 800 600 0 0 1440 900 ")
        #expect(frames.ownFrame(for: notes) == "10 20 800 600 0 0 1440 900 " && frames.ownFrame(for: todo) == nil)
        frames.remember("40 50 500 400 0 0 1440 900 ", for: todo)
        #expect(frames.frame(for: notes) == "10 20 800 600 0 0 1440 900 ")
        #expect(frames.frame(for: URL(fileURLWithPath: "/notes/new.md")) == "40 50 500 400 0 0 1440 900 ")
        #expect(frames.frame(for: nil) == "40 50 500 400 0 0 1440 900 ")
        // A document's place is its last one, and a path is the same however it is spelled.
        frames.remember("1 2 300 200 0 0 1440 900 ", for: URL(fileURLWithPath: "/notes/./a.md"))
        #expect(frames.frame(for: notes) == "1 2 300 200 0 0 1440 900 ")
    }

    /// The places survive the app, and only the most recent ones are kept.
    @Test func keepsTheMostRecentAcrossLaunches() {
        let defaults = suites.make()
        let frames = DocumentWindowFrames(defaults: defaults, limit: 3)
        for index in 1...4 {
            frames.remember("\(index) 0 800 600 0 0 1440 900 ", for: URL(fileURLWithPath: "/notes/\(index).md"))
        }
        frames.remember("9 0 800 600 0 0 1440 900 ", for: URL(fileURLWithPath: "/notes/2.md"))
        let next = DocumentWindowFrames(defaults: defaults, limit: 3)
        #expect(next.frame(for: URL(fileURLWithPath: "/notes/2.md")) == "9 0 800 600 0 0 1440 900 ")
        #expect(next.frame(for: URL(fileURLWithPath: "/notes/4.md")) == "4 0 800 600 0 0 1440 900 ")
        #expect(next.frame(for: URL(fileURLWithPath: "/notes/3.md")) == "3 0 800 600 0 0 1440 900 ")
        // The oldest went: it opens where the last window was.
        #expect(next.frame(for: URL(fileURLWithPath: "/notes/1.md")) == "9 0 800 600 0 0 1440 900 ")
    }
}
