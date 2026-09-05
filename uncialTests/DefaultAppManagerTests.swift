import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Uncial

@MainActor
final class FakeWorkspace: DefaultAppWorkspace {
    var current: URL?
    var setCalls: [URL] = []
    var failNext = false

    init(current: URL?) { self.current = current }

    func defaultApplicationURL(for type: UTType) -> URL? { current }

    func setDefaultApplication(at url: URL, for type: UTType) async throws {
        if failNext { failNext = false; throw CocoaError(.fileReadUnknown) }
        setCalls.append(url)
        current = url
    }
}

@MainActor
@Suite struct DefaultAppManagerTests {
    let uncial = URL(fileURLWithPath: "/Applications/Uncial.app")
    let xcode = URL(fileURLWithPath: "/Applications/Xcode.app")

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
        workspace.current = uncial
        await manager.refresh()
        #expect(manager.isDefault == true)
    }

    @Test func makeDefaultRemembersPreviousAndRemoveRestoresIt() async {
        let workspace = FakeWorkspace(current: xcode)
        let manager = DefaultAppManager(workspace: workspace, ownURL: uncial, defaults: freshDefaults())
        await manager.makeDefault()
        #expect(workspace.setCalls == [uncial])
        #expect(manager.isDefault == true)
        await manager.removeDefault()
        #expect(workspace.setCalls == [uncial, xcode])
        #expect(manager.isDefault == false)
    }

    @Test func removeFallsBackToTextEditWithoutPrevious() async {
        let workspace = FakeWorkspace(current: uncial)
        let manager = DefaultAppManager(workspace: workspace, ownURL: uncial, defaults: freshDefaults())
        await manager.removeDefault()
        #expect(workspace.setCalls == [URL(fileURLWithPath: "/System/Applications/TextEdit.app")])
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
