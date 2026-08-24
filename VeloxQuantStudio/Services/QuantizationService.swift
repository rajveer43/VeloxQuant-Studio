import Foundation
import Observation

@MainActor
protocol QuantizationServiceProtocol: AnyObject {
    /// Starts a quantization job: wires the chosen model + method into a
    /// running `veloxquant serve` instance, which is the same
    /// `KVCacheBuilder.for_model` path the library uses everywhere else —
    /// this app does not reimplement quantization, it drives the existing
    /// engine (see `veloxquant_mlx/cli/serve.py`).
    func startJob(request: QuantizationRequest) -> QuantizationJobHandle
    func stopJob(_ handle: QuantizationJobHandle)
}

struct QuantizationRequest {
    let model: LocalModel
    let method: QuantizationMethod
    let bitWidth: Int
    let parameterOverrides: [String: String]
    let port: Int
}

/// Live handle to a running job — the streaming process plus the SwiftData
/// record it's writing to. Kept separate from `QuantizationJob` (the SwiftData
/// model) because the process controller is not `Codable`/persistable.
@MainActor
@Observable
final class QuantizationJobHandle: Identifiable {
    let id = UUID()
    let request: QuantizationRequest
    let processController: StreamingProcessController
    private(set) var record: QuantizationJob?
    private(set) var readyPayload: ServeReadyPayload?

    init(request: QuantizationRequest, processController: StreamingProcessController) {
        self.request = request
        self.processController = processController
    }

    fileprivate func attach(record: QuantizationJob) {
        self.record = record
    }

    fileprivate func markReady(_ payload: ServeReadyPayload) {
        self.readyPayload = payload
    }
}

/// Decoded form of the `VELOXQUANT_READY {...}` handshake line emitted by
/// `veloxquant serve` — see `emit_ready()` in `cli/serve.py`.
struct ServeReadyPayload: Codable {
    let schemaVersion: Int
    let model: String
    let method: String
    let bits: Int
    let host: String
    let port: Int
    let layerCaches: Int
    let endpoints: Endpoints
    let accountingOnly: Bool
    let accountingNote: String

    struct Endpoints: Codable {
        let openaiBaseURL: String
        let chatCompletions: String
        let completions: String
        let models: String

        enum CodingKeys: String, CodingKey {
            case openaiBaseURL = "openai_base_url"
            case chatCompletions = "chat_completions"
            case completions
            case models
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case model, method, bits, host, port
        case layerCaches = "layer_caches"
        case endpoints
        case accountingOnly = "accounting_only"
        case accountingNote = "accounting_note"
    }
}

@MainActor
final class QuantizationService: QuantizationServiceProtocol {
    private let pythonEnvironment: PythonEnvironmentService
    private let jobHistoryStore: JobHistoryStore
    private static let readyPrefix = "VELOXQUANT_READY "

    init(pythonEnvironment: PythonEnvironmentService, jobHistoryStore: JobHistoryStore) {
        self.pythonEnvironment = pythonEnvironment
        self.jobHistoryStore = jobHistoryStore
    }

    func startJob(request: QuantizationRequest) -> QuantizationJobHandle {
        let controller = StreamingProcessController()
        let handle = QuantizationJobHandle(request: request, processController: controller)

        let paramsJSON = (try? JSONEncoder().encode(request.parameterOverrides))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let record = jobHistoryStore.createJob(
            modelName: request.model.repoID,
            method: request.method.name,
            bitWidth: request.bitWidth,
            parametersJSON: paramsJSON
        )
        handle.attach(record: record)

        controller.onStdoutLine = { [weak self, weak handle] line in
            guard let self, let handle else { return }
            self.jobHistoryStore.appendLog(record, line: line)
            if line.hasPrefix(Self.readyPrefix) {
                let jsonString = String(line.dropFirst(Self.readyPrefix.count))
                if let data = jsonString.data(using: .utf8),
                   let payload = try? JSONDecoder().decode(ServeReadyPayload.self, from: data) {
                    handle.markReady(payload)
                    handle.processController.markRunning()
                }
            }
        }

        guard let interpreter = pythonEnvironment.interpreterPath else {
            jobHistoryStore.complete(record, status: .failed, error: "No Python interpreter configured. Set one in Settings → Compute.")
            return handle
        }

        do {
            try controller.start(executable: interpreter, arguments: Self.serveArguments(for: request))
        } catch {
            jobHistoryStore.complete(record, status: .failed, error: error.localizedDescription)
        }

        return handle
    }

    func stopJob(_ handle: QuantizationJobHandle) {
        handle.processController.stop()
        if let record = handle.record, record.status == .running {
            jobHistoryStore.complete(record, status: .cancelled)
        }
    }

    /// Fields `build_config()` (`serve.py`) always forwards to `KVCacheConfig(...)`
    /// from a dedicated CLI flag, unconditionally — `--bits` as `bit_width_inlier`,
    /// `--seed` as `seed`. Also forwarding either via `--set` — which happens
    /// whenever the selected method declares that field, since the parameter
    /// editor pre-fills every declared field — collides as a duplicate keyword
    /// argument and crashes the server before the model loads.
    private static let serverOwnedOverrideKeys: Set<String> = ["bit_width_inlier", "seed"]

    /// Pure argument-list builder, split out so the `--bits`/`--set` interaction
    /// can be unit-tested without launching a real process.
    static func serveArguments(for request: QuantizationRequest) -> [String] {
        var arguments = [
            "-m", "veloxquant_mlx", "serve",
            "--model", request.model.localPath ?? request.model.repoID,
            "--method", request.method.name,
            "--bits", String(request.bitWidth),
            "--host", "127.0.0.1",
            "--port", String(request.port),
        ]
        for (key, value) in request.parameterOverrides where !value.isEmpty && !serverOwnedOverrideKeys.contains(key) {
            arguments.append(contentsOf: ["--set", "\(key)=\(value)"])
        }
        return arguments
    }
}
