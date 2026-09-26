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
        try SharedSettings.write(theme: .solarized, remoteContent: true, appearance: .system, to: dir)
        #expect(SharedSettings.readTheme(from: dir) == .solarized)
        try SharedSettings.write(theme: .github, remoteContent: true, appearance: .system, to: dir)
        #expect(SharedSettings.readTheme(from: dir) == .github)
    }

    @Test func createsMissingDirectory() throws {
        let dir = try directory().appendingPathComponent("nested/deeper", isDirectory: true)
        try SharedSettings.write(theme: .macOS, remoteContent: true, appearance: .system, to: dir)
        #expect(SharedSettings.readTheme(from: dir) == .macOS)
    }

    @Test func missingOrUnknownValuesReadAsNil() throws {
        let dir = try directory()
        #expect(SharedSettings.readTheme(from: dir) == nil)
        try (["theme": "neon"] as NSDictionary).write(to: dir.appendingPathComponent("settings.plist"))
        #expect(SharedSettings.readTheme(from: dir) == nil)
    }

    @Test func roundTripsRemoteContent() throws {
        let dir = try directory()
        #expect(SharedSettings.readRemoteContent(from: dir) == nil)
        try SharedSettings.write(theme: .github, remoteContent: true, appearance: .system, to: dir)
        #expect(SharedSettings.readRemoteContent(from: dir) == true)
        #expect(SharedSettings.readTheme(from: dir) == .github)
        try SharedSettings.write(theme: .solarized, remoteContent: false, appearance: .system, to: dir)
        #expect(SharedSettings.readRemoteContent(from: dir) == false)
    }

    /// The app's System / Light / Dark choice, for the preview extension; nil when never written or unknown.
    @Test func roundTripsAppearance() throws {
        let dir = try directory()
        #expect(SharedSettings.readAppearance(from: dir) == nil)
        try SharedSettings.write(theme: .github, remoteContent: true, appearance: .dark, to: dir)
        #expect(SharedSettings.readAppearance(from: dir) == .dark)
        #expect(SharedSettings.readTheme(from: dir) == .github && SharedSettings.readRemoteContent(from: dir) == true)
        try SharedSettings.write(theme: .github, remoteContent: true, appearance: .light, to: dir)
        #expect(SharedSettings.readAppearance(from: dir) == .light)
        try (["appearance": "sepia"] as NSDictionary).write(to: dir.appendingPathComponent("settings.plist"))
        #expect(SharedSettings.readAppearance(from: dir) == nil)
    }

    @Test func groupIdentifierIsTeamPrefixed() {
        #expect(SharedSettings.groupIdentifier == "XWTLHG45H7.com.maksimradaev.uncial")
    }
}
