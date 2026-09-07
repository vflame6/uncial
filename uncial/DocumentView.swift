import SwiftUI
import UncialCore

struct DocumentView: View {
    @State private var model: DocumentViewModel
    @State private var mode: EditorMode
    @State private var sync = ScrollSyncController()
    @State private var editorHandle = EditorHandle()
    private let settings: AppSettings

    init(document: MarkdownDocument, fileURL: URL?, settings: AppSettings = .shared) {
        _model = State(initialValue: DocumentViewModel(fileURL: fileURL, initialText: document.text))
        let preferred = settings.defaultEditorMode
        // An empty read-only window is useless: new documents open with the editor visible.
        _mode = State(initialValue: document.text.isEmpty && preferred == .readOnly ? .livePreview : preferred)
        self.settings = settings
    }

    var body: some View {
        HSplitView {
            if mode.showsEditor {
                editor.frame(minWidth: 280)
            }
            if mode.showsPreview {
                preview.frame(minWidth: 280)
            }
        }
        .frame(minWidth: mode == .livePreview ? 600 : 480, minHeight: 320)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Editor Mode", selection: $mode) {
                    ForEach(EditorMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("Editor mode: \(EditorMode.allCases.map { "\($0.title) \($0.shortcut.display)" }.joined(separator: ", "))")
            }
        }
        .focusedSceneValue(\.reloadDocument, ReloadAction { model.reload() })
        .focusedSceneValue(\.saveDocument, SaveAction { model.saveNow() })
        .focusedSceneValue(\.editorMode, $mode)
        .focusedSceneValue(\.findInSource, mode.showsEditor ? FindAction { editorHandle.performFind($0) } : nil)
        .onChange(of: mode) { old, new in
            if old.showsEditor, !new.showsEditor {
                model.saveNow()
            }
            updateSync()
        }
        .onChange(of: settings.syncScrolling) { updateSync() }
        .onAppear { updateSync() }
        .onDisappear { model.saveNow() }
    }

    private func updateSync() {
        sync.isEnabled = mode == .livePreview && settings.syncScrolling
    }

    private var editor: some View {
        VStack(spacing: 0) {
            MarkdownTextView(
                text: model.text,
                palette: settings.theme.editorPalette,
                showsLineNumbers: settings.showLineNumbers,
                autoPairing: settings.autoPairing,
                scrollTarget: sync.editorTarget,
                handle: editorHandle,
                onChange: { model.updateText($0) },
                onScroll: { sync.editorDidScroll(toLine: $0) }
            )
            if let saveError = model.saveError {
                Text("Couldn't save: \(saveError)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let error = model.loadError, model.body.isEmpty {
            ContentUnavailableView("Can't Read Document", systemImage: "doc.text.magnifyingglass", description: Text(error))
        } else {
            WebView(
                body: model.body,
                title: model.title,
                theme: settings.theme,
                baseURL: model.fileURL?.deletingLastPathComponent(),
                scrollTarget: sync.previewTarget,
                onScroll: { sync.previewDidScroll(toLine: $0) }
            )
        }
    }
}
