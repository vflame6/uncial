import SwiftUI
import UncialCore

struct DocumentView: View {
    @State private var model: DocumentViewModel
    @State private var mode: EditorMode
    @State private var sync = ScrollSyncController()
    @State private var editorHandle = EditorHandle()
    @State private var windowHandle = DocumentWindowHandle()
    @State private var previewFind = PreviewFindController()
    private let settings: AppSettings

    init(document: MarkdownDocument, fileURL: URL?, settings: AppSettings = .shared) {
        let model = DocumentViewModel(fileURL: fileURL, initialText: document.text, theme: settings.theme)
        model.autosaves = settings.autosave
        model.externalChangePolicy = settings.externalChangePolicy
        model.remoteContent = settings.loadRemoteContent
        model.attachmentSearch = settings.attachmentSearch
        _model = State(initialValue: model)
        let preferred = settings.defaultEditorMode
        // An empty read-only window is useless: new documents open with the editor visible.
        _mode = State(initialValue: document.text.isEmpty && preferred == .readOnly ? .split : preferred)
        self.settings = settings
    }

    var body: some View {
        VStack(spacing: 0) {
            SplitPanes(showsLeading: mode.showsEditor, showsTrailing: mode.showsPreview, ratio: settings.splitRatio) {
                editor
            } trailing: {
                preview
            }
            if settings.showStatusBar {
                StatusBarView(mode: mode, statistics: model.statistics)
            }
        }
        .frame(minWidth: mode == .split ? 600 : 480, minHeight: 320)
        .background(DocumentWindowBridge(model: model, isEdited: model.needsSavePrompt, handle: windowHandle).frame(width: 0, height: 0))
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
        .focusedSceneValue(\.reloadDocument, ReloadAction { reload() })
        .focusedSceneValue(\.saveDocument, SaveAction { model.saveNow() })
        .focusedSceneValue(\.editorMode, $mode)
        .focusedSceneValue(\.findInDocument, FindAction(supportsReplace: mode.showsEditor) { action in
            if mode.showsEditor {
                editorHandle.performFind(action)
            } else {
                previewFind.perform(action)
            }
        })
        .onChange(of: mode) { old, new in
            if old.showsEditor, !new.showsEditor {
                model.saveIfAutomatic()
            }
            previewFind.hide()
            updateSync()
        }
        .onChange(of: settings.syncScrolling) { updateSync() }
        .onChange(of: settings.theme) { model.theme = settings.theme }
        .onChange(of: settings.autosave) { model.autosaves = settings.autosave }
        .onChange(of: settings.externalChangePolicy) { model.externalChangePolicy = settings.externalChangePolicy }
        .onChange(of: settings.loadRemoteContent) { model.remoteContent = settings.loadRemoteContent }
        .onChange(of: settings.attachmentSearch) { model.attachmentSearch = settings.attachmentSearch }
        .onAppear { updateSync() }
        .onDisappear { model.saveIfAutomatic() }
    }

    /// View ▸ Reload, through the window's guard so unsaved edits get a confirmation sheet.
    private func reload() {
        if let guardian = windowHandle.guardian {
            Task { await guardian.reload() }
        } else {
            model.reload()
        }
    }

    private func updateSync() {
        sync.isEnabled = mode == .split && settings.syncScrolling
    }

    private var editor: some View {
        VStack(spacing: 0) {
            MarkdownTextView(
                text: model.text,
                theme: settings.theme,
                fontSize: CGFloat(settings.effectiveTextSize),
                showsLineNumbers: settings.showLineNumbers,
                autoPairing: settings.autoPairing,
                continueLists: settings.continueLists,
                presentation: mode.presentation,
                readableWidth: settings.readableLineWidth,
                baseURL: model.fileURL?.deletingLastPathComponent(),
                loadsRemoteImages: settings.loadRemoteContent,
                attachmentSearch: settings.attachmentSearch,
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

    private var preview: some View {
        VStack(spacing: 0) {
            if previewFind.isVisible, !mode.showsEditor {
                PreviewFindBar(controller: previewFind)
            }
            previewContent
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if let error = model.loadError, model.body.isEmpty {
            ContentUnavailableView("Can't Read Document", systemImage: "doc.text.magnifyingglass", description: Text(error))
        } else {
            WebView(
                body: model.body,
                title: model.title,
                theme: settings.theme,
                textScale: settings.textScale,
                lineNumbers: settings.showLineNumbers,
                baseURL: model.fileURL?.deletingLastPathComponent(),
                remoteContent: settings.loadRemoteContent,
                attachments: settings.attachmentSearch,
                handle: previewFind.handle,
                scrollTarget: sync.previewTarget,
                onScroll: { sync.previewDidScroll(toLine: $0) }
            )
        }
    }
}
