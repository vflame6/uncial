import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Uncial

@MainActor
final class FakeWorkspace: DefaultAppWorkspace {
    /// The handler per type identifier; a missing entry is a type without a handler.
    var current: [String: URL] = [:]
    var setCalls: [URL] = []
    var setTypes: [UTType] = []
    var failNext = false

    init(current: URL?) {
        for type in DefaultAppManager.types { self.current[type.identifier] = current }
    }

    func setAll(_ url: URL?) {
        for type in DefaultAppManager.types { current[type.identifier] = url }
    }

    func defaultApplicationURL(for type: UTType) -> URL? { current[type.identifier] }

    func setDefaultApplication(at url: URL, for type: UTType) async throws {
        if failNext { failNext = false; throw CocoaError(.fileReadUnknown) }
        setCalls.append(url)
        setTypes.append(type)
        current[type.identifier] = url
    }
}

@MainActor
@Suite struct DefaultAppManagerTests {
    let uncial = URL(fileURLWithPath: "/Applications/Uncial.app")
    let xcode = URL(fileURLWithPath: "/Applications/Xcode.app")
    let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

    private func freshDefaults() -> UserDefaults {
        let name = "uncial-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func detectsWhetherUncialIsDefault() async {
        let workspace = FakeWorkspace(current: xcode)
        let manager = DefaultAppManager(workspace: workspace, ownURL: uncial, defaults: freshDefaults())
        await manager.refresh()
        #expect(manager.isDefault == false)
        #expect(manager.currentDefaultName == "Xcode")
        workspace.setAll(uncial)
        await manager.refresh()
        #expect(manager.isDefault == true)
        #expect(manager.currentDefaultName == "Uncial")
    }

    @Test func everyTypeMustBeUncialToCountAsDefault() async {
        let workspace = FakeWorkspace(current: uncial)
        workspace.current[UTType.markdownVariant.identifier] = xcode
        let manager = DefaultAppManager(workspace: workspace, ownURL: uncial, defaults: freshDefaults())
        await manager.refresh()
        #expect(manager.isDefault == false)
        #expect(manager.currentDefaultName == "Xcode")
    }

    @Test func makeDefaultRemembersPreviousAndRemoveRestoresIt() async {
        let workspace = FakeWorkspace(current: xcode)
        let manager = DefaultAppManager(workspace: workspace, ownURL: uncial, defaults: freshDefaults())
        await manager.makeDefault()
        #expect(workspace.setCalls == [uncial, uncial])
        #expect(workspace.setTypes == [.markdown, .markdownVariant])
        #expect(manager.isDefault == true)
        await manager.removeDefault()
        #expect(workspace.setCalls == [uncial, uncial, xcode, xcode])
        #expect(workspace.setTypes == [.markdown, .markdownVariant, .markdown, .markdownVariant])
        #expect(manager.isDefault == false)
    }

    @Test func variantWithoutAHandlerRestoresToTheMarkdownTypesPrevious() async {
        let workspace = FakeWorkspace(current: xcode)
        workspace.current[UTType.markdownVariant.identifier] = nil
        let manager = DefaultAppManager(workspace: workspace, ownURL: uncial, defaults: freshDefaults())
        await manager.makeDefault()
        #expect(manager.restoreTarget(for: .markdownVariant) == xcode)
        await manager.removeDefault()
        #expect(workspace.setCalls == [uncial, uncial, xcode, xcode])
    }

    @Test func removeFallsBackToTextEditWithoutPrevious() async {
        let workspace = FakeWorkspace(current: uncial)
        let manager = DefaultAppManager(workspace: workspace, ownURL: uncial, defaults: freshDefaults())
        await manager.removeDefault()
        #expect(workspace.setCalls == [textEdit, textEdit])
    }

    @Test func surfacesErrors() async {
        let workspace = FakeWorkspace(current: xcode)
        workspace.failNext = true
        let manager = DefaultAppManager(workspace: workspace, ownURL: uncial, defaults: freshDefaults())
        await manager.makeDefault()
        #expect(manager.errorMessage != nil)
        #expect(manager.isDefault == false)
    }
}
