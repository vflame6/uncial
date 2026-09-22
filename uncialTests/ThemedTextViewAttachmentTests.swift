import AppKit
import Testing
import UncialCore
@testable import Uncial

@MainActor
@Suite struct ThemedTextViewAttachmentTests {
    private static let pngPixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

    /// A document folder, a folder of sources beside it, and an editor on "one\ntwo" with the caret after "one".
    private func fixture() throws -> (directory: URL, sources: URL, editor: ThemedTextView) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("uncial-paste-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("notes", isDirectory: true)
        let sources = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let editor = ThemedTextView.standalone()
        editor.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        editor.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        editor.baseURL = directory
        editor.attachmentSearch = AttachmentSearch(searchesParents: false)
        editor.replaceText(with: "one\ntwo")
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        return (directory, sources, editor)
    }

    /// A private pasteboard, so the tests never touch the general one.
    private func pasteboard() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("uncial-test-\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    @Test func pastesAFileAsACopiedAttachment() throws {
        let (directory, sources, editor) = try fixture()
        let source = sources.appendingPathComponent("pic.png")
        try Self.pngPixel.write(to: source)
        let board = pasteboard()
        #expect(board.writeObjects([source as NSURL]))
        #expect(editor.readSelection(from: board))
        #expect(editor.string == "one![pic](attachments/pic.png)\ntwo")
        #expect(try Data(contentsOf: directory.appendingPathComponent("attachments/pic.png")) == Self.pngPixel)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(editor.undoManager?.canUndo == true)
        editor.undoManager?.undo()
        #expect(editor.string == "one\ntwo")
    }

    @Test func pastesPictureDataAsAFile() throws {
        let (directory, _, editor) = try fixture()
        editor.attachmentDestination = .documentFolder
        let board = pasteboard()
        board.setData(Self.pngPixel, forType: .png)
        #expect(editor.readSelection(from: board))
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.count == 1)
        let name = try #require(files.first)
        #expect(name.hasPrefix("pasted-image-") && name.hasSuffix(".png"))
        #expect(editor.string == "one![\((name as NSString).deletingPathExtension)](\(name))\ntwo")
        #expect(try Data(contentsOf: directory.appendingPathComponent(name)) == Self.pngPixel)
    }

    @Test func textStillPastesAsText() throws {
        let (directory, _, editor) = try fixture()
        let board = pasteboard()
        board.setString("hey", forType: .string)
        #expect(editor.readSelection(from: board))
        #expect(editor.string == "onehey\ntwo")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("attachments").path))
    }

    @Test func dropsFilesAtTheDropPoint() throws {
        let (directory, sources, editor) = try fixture()
        #expect(editor.registeredDraggedTypes.contains(.fileURL))
        // Set up like the app (plain text, no graphics, in a scroll view in a window): NSTextView's own
        // registration on the way in must not drop the attachment types.
        editor.isRichText = false
        editor.importsGraphics = false
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.documentView = editor
        let window = NSWindow(contentRect: scrollView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scrollView
        editor.isEditable = true
        #expect(editor.window === window)
        #expect(editor.registeredDraggedTypes.contains(.fileURL) && editor.registeredDraggedTypes.contains(.png))
        let source = sources.appendingPathComponent("notes.pdf")
        try Data("pdf".utf8).write(to: source)
        let board = pasteboard()
        #expect(board.writeObjects([source as NSURL]))
        let layoutManager = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        layoutManager.ensureLayout(for: container)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: 4, length: 1), in: container)
        let origin = editor.textContainerOrigin
        let point = NSPoint(x: rect.minX + origin.x + 1, y: rect.midY + origin.y)
        let info = DragInfo(pasteboard: board, location: editor.convert(point, to: nil))
        #expect(editor.dragOperation(for: info, type: .fileURL) == .copy)
        #expect(editor.performDragOperation(info))
        #expect(editor.string == "one\n[notes.pdf](attachments/notes.pdf)two")
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("attachments/notes.pdf").path))
    }
}

/// The two things `performDragOperation` reads from a drag.
nonisolated private final class DragInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingLocation: NSPoint

    init(pasteboard: NSPasteboard, location: NSPoint) {
        draggingPasteboard = pasteboard
        draggingLocation = location
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    var numberOfValidItemsForDrop = 1
    var draggingFormation = NSDraggingFormation.default
    var animatesToDestination = false

    func slideDraggedImage(to screenPoint: NSPoint) {}
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
