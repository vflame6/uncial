import SwiftUI

@main
struct UncialApp: App {
    @FocusedValue(\.reloadDocument) private var reloadDocument

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { configuration in
            DocumentView(document: configuration.document, fileURL: configuration.fileURL)
        }
        .defaultSize(width: 900, height: 760)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Reload") { reloadDocument?.run() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(reloadDocument == nil)
            }
        }
    }
}
