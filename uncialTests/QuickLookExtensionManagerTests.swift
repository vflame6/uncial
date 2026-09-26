import Foundation
import Testing
import UncialCore
@testable import Uncial

@MainActor
@Suite struct QuickLookExtensionManagerTests {
    private struct Failure: Error {}

    /// A failed Install's error goes once a refresh finds the extension enabled after all (switched on
    /// in System Settings), instead of staying next to a healthy status for the session.
    @Test func errorGoesOnceTheGoalIsReached() async {
        var election = "-    com.maksimradaev.uncial.QuickLook(1.0)"
        var failElection = true
        let manager = QuickLookExtensionManager()
        manager.runCommand = { executable, arguments in
            if arguments.first == "-m" { return election }
            if arguments.first == "-e", failElection { throw Failure() }
            return ""
        }
        await manager.install()
        #expect(manager.errorMessage != nil && manager.state == .disabled)
        await manager.refresh()
        #expect(manager.errorMessage != nil)
        election = "+    com.maksimradaev.uncial.QuickLook(1.0)"
        failElection = false
        await manager.refresh()
        #expect(manager.state == .enabled && manager.errorMessage == nil)
    }
}
