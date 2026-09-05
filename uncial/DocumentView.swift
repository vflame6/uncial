import SwiftUI

struct DocumentView: View {
    @State private var model: DocumentViewModel

    init(document: MarkdownDocument, fileURL: URL?) {
        _model = State(initialValue: DocumentViewModel(fileURL: fileURL, initialText: document.text))
    }

    var body: some View {
        content
            .frame(minWidth: 480, minHeight: 320)
            .focusedSceneValue(\.reloadDocument, ReloadAction { model.reload() })
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.error, model.html.isEmpty {
            ContentUnavailableView("Can't Read Document", systemImage: "doc.text.magnifyingglass", description: Text(error))
        } else {
            WebView(html: model.html, baseURL: model.fileURL?.deletingLastPathComponent())
        }
    }
}
