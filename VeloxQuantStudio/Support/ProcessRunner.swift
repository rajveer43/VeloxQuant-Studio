import Foundation

/// Result of a completed (non-streaming) subprocess run.
struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ProcessRunnerError: LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason): "Failed to launch process: \(reason)"
        }
    }
}

/// Thin `Process` wrapper for one-shot CLI calls (`veloxquant methods --json`,
/// interpreter validation, `veloxquant recommend`). Long-running, streaming
/// processes (`veloxquant serve`, `veloxquant precompute`) use
/// `StreamingProcessController` instead.
enum ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let currentDirectory {
                process.currentDirectoryURL = currentDirectory
            }
            if let environment {
                process.environment = environment
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
                return
            }

            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let result = ProcessResult(
                exitCode: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            )
            continuation.resume(returning: result)
        }
    }
}
