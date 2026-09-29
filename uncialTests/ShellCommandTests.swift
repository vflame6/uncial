import Foundation
import Testing
@testable import Uncial

@Suite struct ShellCommandTests {
    @Test func capturesStandardOutput() async throws {
        let output = try await ShellCommand.run("/bin/echo", ["hello"])
        #expect(output == "hello\n")
    }

    /// The tool's own words are the error a manager shows.
    @Test func nonZeroExitThrowsWithOutput() async {
        let failure = await #expect(throws: ShellCommand.Failure.self) {
            try await ShellCommand.run("/bin/sh", ["-c", "echo boom >&2; exit 3"])
        }
        #expect(failure?.status == 3 && failure?.localizedDescription == "boom")
    }
}
