import Testing
@testable import Uncial

@Suite struct ShellCommandTests {
    @Test func capturesStandardOutput() async throws {
        let output = try await ShellCommand.run("/bin/echo", ["hello"])
        #expect(output == "hello\n")
    }

    @Test func nonZeroExitThrowsWithOutput() async {
        await #expect(throws: ShellCommand.Failure.self) {
            try await ShellCommand.run("/bin/sh", ["-c", "echo boom >&2; exit 3"])
        }
    }
}
