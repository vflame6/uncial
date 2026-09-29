import AppKit
import UniformTypeIdentifiers

/// The save panel of File ▸ Export…: a Format popup (PDF, HTML) under the name switches the name's
/// extension and the one type the panel allows. It opens in the document's folder, named after it.
final class ExportPanel: NSObject {
    let panel = NSSavePanel()
    private(set) var format: ExportFormat
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)

    init(format: ExportFormat, documentName: String, directory: URL?) {
        self.format = format
        super.init()
        panel.title = "Export"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let directory {
            panel.directoryURL = directory
        }
        panel.nameFieldStringValue = documentName
        popup.addItems(withTitles: ExportFormat.allCases.map(\.title))
        popup.target = self
        popup.action = #selector(formatChosen(_:))
        let row = NSStackView(views: [NSTextField(labelWithString: "Format:"), popup])
        row.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        row.setFrameSize(row.fittingSize)
        panel.accessoryView = row
        select(format)
    }

    /// Shows `format` in the popup, allows only its type and gives the name its extension.
    func select(_ format: ExportFormat) {
        self.format = format
        popup.selectItem(at: ExportFormat.allCases.firstIndex(of: format) ?? 0)
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = format.fileName(for: panel.nameFieldStringValue)
    }

    @objc private func formatChosen(_ sender: NSPopUpButton) {
        select(ExportFormat.allCases[sender.indexOfSelectedItem])
    }

    /// Shows the panel as a sheet on `window` (app-modal without one) and hands over the chosen file and
    /// format, or nil on Cancel. The panel keeps this object alive until then.
    func begin(on window: NSWindow?, completion: @escaping ((url: URL, format: ExportFormat)?) -> Void) {
        let finish: (NSApplication.ModalResponse) -> Void = { [self] response in
            completion(response == .OK ? panel.url.map { ($0, format) } : nil)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }
}
