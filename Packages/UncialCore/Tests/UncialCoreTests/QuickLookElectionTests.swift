import Testing
@testable import UncialCore

@Suite struct QuickLookElectionTests {
    @Test func emptyOutputMeansUnregistered() {
        #expect(QuickLookElection.parse("") == .unregistered)
        #expect(QuickLookElection.parse("\n") == .unregistered)
    }

    @Test func electionPrefixes() {
        #expect(QuickLookElection.parse("-    com.maksimradaev.uncial.QuickLook(1.0)\n") == .disabled)
        #expect(QuickLookElection.parse("+    com.maksimradaev.uncial.QuickLook(1.0)\n") == .enabled)
        #expect(QuickLookElection.parse("     com.maksimradaev.uncial.QuickLook(1.0)\n") == .enabled)
        #expect(QuickLookElection.parse("!    com.maksimradaev.uncial.QuickLook(1.0)\n") == .enabled)
        #expect(QuickLookElection.parse("=    com.maksimradaev.uncial.QuickLook(1.0)\n") == .enabled)
        #expect(QuickLookElection.parse("?    com.maksimradaev.uncial.QuickLook(1.0)\n") == .unknown)
    }

    @Test func firstLineWins() {
        #expect(QuickLookElection.parse("-    a(1.0)\n+    a(1.0)\n") == .disabled)
    }
}
