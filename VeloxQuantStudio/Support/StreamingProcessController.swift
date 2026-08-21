import Foundation
import Observation

/// Owns a long-running `Process` (a `veloxquant precompute`/`benchmark`/`serve`
/// invocation), streaming stdout/stderr line-by-line for a live log pane and
/// exposing a small lifecycle state machine.
///
/// Mirrors the `ServerSupervisor` design in `veloxquant_mlx/ui/supervisor.py`:
/// state flips to `.running` only on an explicit readiness signal (or, for
/// jobs with no handshake, on clean process exit) — never on a timer.
@MainActor
@Observable
final class StreamingProcessController {
    enum State: Equatable {
        case idle
        case starting
        case running
        case finished(exitCode: Int32)
        case failed(reason: String)
    }

    private(set) var state: State = .idle
    private(set) var logLines: [String] = []

    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?

    /// Called for every line of stdout, before it's appended to `logLines`.
    /// Used by callers that need to watch for a handshake line
    /// (`VELOXQUANT_READY {...}`) without re-parsing the whole buffer.
    var onStdoutLine: ((String) -> Void)?

    func start(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) throws {
        guard process == nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] terminated in
            Task { @MainActor in
                self?.handleTermination(terminated)
            }
        }

        self.process = process
        self.stdoutHandle = stdoutPipe.fileHandleForReading
        self.stderrHandle = stderrPipe.fileHandleForReading
        self.state = .starting
        self.logLines = []

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.append(text) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.append(text) }
        }

        do {
            try process.run()
        } catch {
            self.process = nil
            state = .failed(reason: error.localizedDescription)
            throw error
        }
    }

    /// Marks the process as running without waiting for exit — used once a
    /// readiness handshake line has been observed (e.g. `veloxquant serve`).
    func markRunning() {
        if state == .starting {
            state = .running
        }
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.interrupt()
        // Give it a moment to exit cleanly before escalating.
        Task {
            try? await Task.sleep(for: .seconds(2))
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private func append(_ text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            let string = String(line)
            logLines.append(string)
            onStdoutLine?(string)
        }
    }

    private func handleTermination(_ process: Process) {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        let code = process.terminationStatus
        self.process = nil

        switch state {
        case .running, .starting:
            state = code == 0 ? .finished(exitCode: code) : .failed(reason: "Process exited with code \(code).")
        default:
            break
        }
    }
}
