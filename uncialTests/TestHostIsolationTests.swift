import AppKit
import Testing
import UncialCore
@testable import Uncial

/// `xcodebuild test` runs the unit tests inside Uncial itself, under the app's bundle id, so whatever
/// the host does at launch lands in the user's real environment.
@MainActor
@Suite struct TestHostIsolationTests {
    /// The Quick Look extension the user runs reads the App Group: the test host publishes neither its
    /// settings nor its diagrams there.
    @Test func publishesNothingToQuickLook() throws {
        #expect(DiagramWebRenderer.shared.store == nil)
        let launch = try #require(NSRunningApplication.current.launchDate)
        let settings = SharedSettings.containerURL()?.appendingPathComponent("settings.plist")
        if let modified = try? settings?.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            #expect(modified < launch)
        }
        #expect(AppDelegate.isTestHost(ProcessInfo.processInfo.environment))
        #expect(!AppDelegate.isTestHost(["HOME": "/Users/someone", "PATH": "/usr/bin:/bin"]))
    }

    /// A suite a test writes to is stored in its own temporary folder, gone after `removeAll()`, never
    /// in the user's ~/Library/Preferences.
    @Test func preferenceSuitesStayOutOfTheUsersPreferences() async throws {
        let suites = PreferenceSuites()
        let defaults = suites.make()
        defaults.set(true, forKey: "written")
        let stored = { (try? FileManager.default.contentsOfDirectory(atPath: suites.directory.path)) ?? [] }
        // cfprefsd writes the file a moment later.
        for _ in 0..<60 where stored().isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(stored() == ["defaults-1.plist"])
        let named = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suites.directory.lastPathComponent).plist")
        #expect(!FileManager.default.fileExists(atPath: named.path))
        suites.removeAll()
        #expect(!FileManager.default.fileExists(atPath: suites.directory.path))
    }
}
