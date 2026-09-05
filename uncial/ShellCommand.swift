import Foundation

/// Runs a command-line tool and returns its combined stdout/stderr.
nonisolated enum ShellCommand {
    nonisolated struct Failure: LocalizedError {
        let command: String
        let status: Int32
        let output: String

        var errorDescription: String? {
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "\(command) exited with status \(status)" : detail
        }
    }

    static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { process in
                let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let command = ([executable] + arguments).joined(separator: " ")
                    continuation.resume(throwing: Failure(command: command, status: process.terminationStatus, output: output))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
