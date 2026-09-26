import Testing
import UncialCore
@testable import Uncial

/// The footers that describe the chosen settings in one or two sentences.
@MainActor
@Suite struct SettingsTextTests {
    @Test func attachmentsFooterDescribesTheSearch() {
        let everywhere = GeneralSettingsView.attachmentsFooter(for: AttachmentSearch(), destination: .attachmentsFolder)
        #expect(everywhere == "A missing image or linked file is looked for in the “attachments” folder next to the document, then in the folders above it and their “attachments” folders, up to your home folder. Pasted or dropped files the document already reaches, such as those in its folder and other notes, are linked where they are; other files and pictures go to the “attachments” folder next to the document, created as needed.")

        let toRoot = GeneralSettingsView.attachmentsFooter(for: AttachmentSearch(directoryName: "assets", boundary: .root), destination: .nearestAttachmentsFolder)
        #expect(toRoot.hasPrefix("A missing image or linked file is looked for in the “assets” folder next to the document, then in the folders above it and their “assets” folders, up to the root of the disk."))
        #expect(toRoot.hasSuffix("Pasted or dropped files the document already reaches, such as those in its folder and other notes, are linked where they are; other files and pictures go to the first “assets” folder found above the document, or to one created next to it."))

        let nextToTheDocument = GeneralSettingsView.attachmentsFooter(for: AttachmentSearch(searchesParents: false), destination: .nearestAttachmentsFolder)
        #expect(nextToTheDocument == "A missing image or linked file is looked for in the “attachments” folder next to the document. Pasted or dropped files the document already reaches, such as those in its folder and other notes, are linked where they are; other files and pictures go to the “attachments” folder next to the document, created as needed.")

        let foldersOnly = GeneralSettingsView.attachmentsFooter(for: AttachmentSearch(directoryName: " ", searchesParents: true), destination: .attachmentsFolder)
        #expect(foldersOnly == "A missing image or linked file is looked for in the folders above the document, up to your home folder. Pasted or dropped files the document already reaches, such as those in its folder and other notes, are linked where they are; other files and pictures go next to the document.")

        let nowhere = GeneralSettingsView.attachmentsFooter(for: .direct, destination: .documentFolder)
        #expect(nowhere == "A missing image or linked file is not looked for elsewhere. Pasted or dropped files the document already reaches, such as those in its folder and other notes, are linked where they are; other files and pictures go next to the document.")

        let documentFolder = GeneralSettingsView.attachmentsFooter(for: AttachmentSearch(), destination: .documentFolder)
        #expect(documentFolder.hasSuffix("Pasted or dropped files the document already reaches, such as those in its folder and other notes, are linked where they are; other files and pictures go next to the document."))
    }

    @Test func savingFooterDescribesTheChosenPolicy() {
        let manual = EditorSettingsView.savingFooter(autosave: false, policy: .ask)
        #expect(manual == "Edits are written when you save with \(AppShortcut.save.display). Closing a window, quitting or reloading with unsaved edits asks first. If another program changes the file while you have unsaved edits, Uncial asks whether to keep them or reload.")

        let automatic = EditorSettingsView.savingFooter(autosave: true, policy: .keepLocal)
        #expect(automatic == "Edits are written to the file half a second after you stop typing. If another program changes the file while you have unsaved edits, your edits replace its new contents at the next save.")

        let reload = EditorSettingsView.savingFooter(autosave: true, policy: .reload)
        #expect(reload.hasSuffix("If another program changes the file while you have unsaved edits, the file's new contents replace them."))
    }

    @Test func settingsOpenOnGeneral() {
        #expect(SettingsView.Tab.allCases.first == .general)
    }
}
