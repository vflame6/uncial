import SwiftUI

@main
struct UncialApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @FocusedValue(\.reloadDocument) private var reloadDocument
    @FocusedValue(\.saveDocument) private var saveDocument
    @FocusedValue(\.editorMode) private var editorMode
    @FocusedValue(\.findInSource) private var findInSource

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { configuration in
            DocumentView(document: configuration.document, fileURL: configuration.fileURL)
        }
        .defaultSize(width: 1000, height: 760)
        .commands {
            CommandGroup(before: .newItem) {
                Button("New…") { NewDocumentCommand.run() }
                    .keyboardShortcut(.newDocument)
            }
            // The stock group also carries Save As…, Duplicate, Rename…, Move To… and Revert To, which
            // act on NSDocument's read-only copy of the text. Edits are written through by the model.
            CommandGroup(replacing: .saveItem) {
                Button("Close") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut(.close)
                Button("Close All") {
                    for window in NSApp.windows where window.isVisible && window.styleMask.contains(.closable) {
                        window.performClose(nil)
                    }
                }
                .keyboardShortcut(.closeAll)
                Divider()
                Button("Save") { saveDocument?.run() }
                    .keyboardShortcut(.save)
                    .disabled(saveDocument == nil)
            }
            // SwiftUI's Edit menu has no Find items; these drive the editor's find bar (replace row included).
            CommandGroup(after: .pasteboard) {
                Menu("Find") {
                    findItem(.find, .showFindInterface)
                    findItem(.findAndReplace, .showReplaceInterface)
                    findItem(.findNext, .nextMatch)
                    findItem(.findPrevious, .previousMatch)
                    findItem(.useSelectionForFind, .setSearchString)
                }
            }
            CommandGroup(after: .toolbar) {
                ForEach(EditorMode.allCases) { mode in
                    Toggle(mode.title, isOn: Binding(
                        get: { editorMode?.wrappedValue == mode },
                        set: { if $0 { editorMode?.wrappedValue = mode } }
                    ))
                    .keyboardShortcut(mode.shortcut)
                    .disabled(editorMode == nil)
                }
                Button("Toggle Editor Mode") {
                    if let editorMode {
                        editorMode.wrappedValue = editorMode.wrappedValue.next
                    }
                }
                .keyboardShortcut(.toggleEditorMode)
                .disabled(editorMode == nil)
                Divider()
                Button("Reload") { reloadDocument?.run() }
                    .keyboardShortcut(.reload)
                    .disabled(reloadDocument == nil)
            }
        }

        Settings {
            SettingsView()
        }
    }

    private func findItem(_ shortcut: AppShortcut, _ action: NSTextFinder.Action) -> some View {
        Button(shortcut.title) { findInSource?.perform(action) }
            .keyboardShortcut(shortcut)
            .disabled(findInSource == nil)
    }
}
