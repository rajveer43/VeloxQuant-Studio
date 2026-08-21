import Foundation
import Observation

/// Locates and validates a Python interpreter with `veloxquant_mlx` (and its
/// `mlx_lm` dependency) importable. This is the single biggest source of
/// "it doesn't work on my machine" per `docs/control-panel-plan.md` §Q1, so
/// every other service routes subprocess calls through here rather than
/// hardcoding `python3`.
@MainActor
@Observable
final class PythonEnvironmentService {
    enum Status: Equatable {
        case unknown
        case checking
        case valid(interpreterPath: String, veloxquantVersion: String)
        case invalid(reason: String)
    }

    private(set) var status: Status = .unknown

    /// Candidate interpreters tried in order before falling back to a saved
    /// user override. Covers Homebrew, pyenv, and a plain venv at the repo
    /// root — the common ways an MLX dev environment gets set up on macOS.
    private static let candidatePaths: [String] = [
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/usr/bin/python3",
    ]

    private let defaultsKey = "veloxquant.pythonInterpreterPath"

    var interpreterPath: String? {
        if case .valid(let path, _) = status { return path }
        return nil
    }

    func restoreSavedInterpreter() async {
        if let saved = UserDefaults.standard.string(forKey: defaultsKey) {
            await validate(path: saved)
            if case .valid = status { return }
        }
        await autoDetect()
    }

    func autoDetect() async {
        status = .checking
        for path in Self.candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                await validate(path: path)
                if case .valid = status { return }
            }
        }
        // Fall back to whatever `python3` resolves to on PATH via a login
        // shell, so pyenv/conda shims that aren't at a fixed path still work.
        if let resolved = await resolveViaLoginShell() {
            await validate(path: resolved)
            if case .valid = status { return }
        }
        status = .invalid(reason: "No Python interpreter with veloxquant_mlx installed was found.")
    }

    /// Explicit user pick from a file picker (Settings screen).
    func selectInterpreter(at path: String) async {
        await validate(path: path)
        if case .valid = status {
            UserDefaults.standard.set(path, forKey: defaultsKey)
        }
    }

    /// Runs `<python> -c "import veloxquant_mlx; print(veloxquant_mlx.__version__)"`
    /// and only accepts the interpreter if that import succeeds.
    private func validate(path: String) async {
        status = .checking
        do {
            let result = try await ProcessRunner.run(
                executable: path,
                arguments: ["-c", "import veloxquant_mlx; print(veloxquant_mlx.__version__)"]
            )
            guard result.exitCode == 0 else {
                status = .invalid(reason: "veloxquant_mlx is not importable with \(path).\n\(result.stderr)")
                return
            }
            let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            status = .valid(interpreterPath: path, veloxquantVersion: version)
        } catch {
            status = .invalid(reason: error.localizedDescription)
        }
    }

    private func resolveViaLoginShell() async -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let result = try? await ProcessRunner.run(
            executable: shell,
            arguments: ["-l", "-c", "command -v python3"]
        ), result.exitCode == 0 else {
            return nil
        }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
