import Foundation
import Testing
@testable import UncialCore

@Suite struct SharedSettingsTests {
    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uncial-shared-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func roundTripsTheme() throws {
        let dir = try directory()
        try SharedSettings.write(theme: .solarized, to: dir)
        #expect(SharedSettings.readTheme(from: dir) == .solarized)
        try SharedSettings.write(theme: .github, to: dir)
        #expect(SharedSettings.readTheme(from: dir) == .github)
    }

    @Test func createsMissingDirectory() throws {
        let dir = try directory().appendingPathComponent("nested/deeper", isDirectory: true)
        try SharedSettings.write(theme: .macOS, to: dir)
        #expect(SharedSettings.readTheme(from: dir) == .macOS)
    }

    @Test func missingOrUnknownValuesReadAsNil() throws {
        let dir = try directory()
        #expect(SharedSettings.readTheme(from: dir) == nil)
        try (["theme": "neon"] as NSDictionary).write(to: dir.appendingPathComponent("settings.plist"))
        #expect(SharedSettings.readTheme(from: dir) == nil)
    }

    @Test func groupIdentifierIsTeamPrefixed() {
        #expect(SharedSettings.groupIdentifier == "XWTLHG45H7.com.maksimradaev.uncial")
    }
}
