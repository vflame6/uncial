import Foundation
import Testing
@testable import UncialCore

@Suite struct SharedSettingsTests {
    private let directory = TemporaryDirectory()

    /// What the app publishes is what the Quick Look extensions read: the theme, the remote-content
    /// choice and the System / Light / Dark appearance, each time they are written.
    @Test func roundTripsEverySetting() throws {
        try SharedSettings.write(theme: .solarized, remoteContent: false, appearance: .dark, to: directory.url)
        #expect(SharedSettings.readTheme(from: directory.url) == .solarized)
        #expect(SharedSettings.readRemoteContent(from: directory.url) == false)
        #expect(SharedSettings.readAppearance(from: directory.url) == .dark)
        try SharedSettings.write(theme: .github, remoteContent: true, appearance: .light, to: directory.url)
        #expect(SharedSettings.readTheme(from: directory.url) == .github)
        #expect(SharedSettings.readRemoteContent(from: directory.url) == true)
        #expect(SharedSettings.readAppearance(from: directory.url) == .light)
    }

    @Test func createsMissingDirectory() throws {
        let nested = directory.url("nested/deeper", isDirectory: true)
        try SharedSettings.write(theme: .macOS, remoteContent: true, appearance: .system, to: nested)
        #expect(SharedSettings.readTheme(from: nested) == .macOS)
    }

    /// Nothing published yet, or a value this version does not know, reads as nil: the extension
    /// falls back to its own default.
    @Test func missingOrUnknownValuesReadAsNil() throws {
        #expect(SharedSettings.readTheme(from: directory.url) == nil)
        #expect(SharedSettings.readRemoteContent(from: directory.url) == nil)
        #expect(SharedSettings.readAppearance(from: directory.url) == nil)
        try (["theme": "neon", "appearance": "sepia"] as NSDictionary).write(to: directory.url("settings.plist"))
        #expect(SharedSettings.readTheme(from: directory.url) == nil)
        #expect(SharedSettings.readAppearance(from: directory.url) == nil)
    }

    @Test func groupIdentifierIsTeamPrefixed() {
        #expect(SharedSettings.groupIdentifier == "XWTLHG45H7.com.maksimradaev.uncial")
    }
}
