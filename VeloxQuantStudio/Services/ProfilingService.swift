import Foundation

@MainActor
protocol ProfilingServiceProtocol {
    /// Runs `veloxquant profile --json` — a real generation pass through the
    /// requested model/method/bits with per-layer KV-cache latency and memory
    /// wrapped by `MLXCacheProfiler` (see `veloxquant_mlx/profiling/kv_profiler.py`
    /// and `cli/profile.py`, issue #45). Post-hoc only: the profiler has no
    /// incremental/streaming hook, so this returns once the full run
    /// (model load + generation) completes.
    func profile(request: ProfileRequest) async throws -> ProfileResponse
}

struct ProfileRequest {
    let model: LocalModel
    let method: String
    let bitWidth: Int
    let parameterOverrides: [String: String]
    let prompt: String
    let maxTokens: Int

    init(
        model: LocalModel,
        method: String,
        bitWidth: Int,
        parameterOverrides: [String: String] = [:],
        prompt: String = "The quick brown fox jumps over the lazy dog.",
        maxTokens: Int = 64
    ) {
        self.model = model
        self.method = method
        self.bitWidth = bitWidth
        self.parameterOverrides = parameterOverrides
        self.prompt = prompt
        self.maxTokens = maxTokens
    }
}

/// Mirrors the JSON `cli/profile.py` prints. Servable caches implement one
/// fused `update_and_fetch` call rather than separate quantize/dequantize/
/// write steps, so each layer reports a single `computeLatencyMs` — see
/// `MLXCacheProfiler`'s docstring upstream. `accountingOnly` defaults to
/// `true` on decode (see `CodingKeys`/`init(from:)`) so a future CLI build
/// that omits the field fails toward *not* overstating a memory win, matching
/// `ServeReadyPayload.accountingOnly`'s always-true contract.
struct ProfileResponse: Codable {
    let schemaVersion: Int
    let model: String
    let method: String
    let bits: Int
    let accountingOnly: Bool
    let accountingNote: String
    let layers: [LayerResult]
    let summary: Summary

    struct LayerResult: Codable, Identifiable {
        let layerIndex: Int
        let computeLatencyMs: Double
        let isFused: Bool
        let peakMemoryBytes: Int
        let compressionRatio: Double

        var id: Int { layerIndex }

        enum CodingKeys: String, CodingKey {
            case layerIndex = "layer_index"
            case computeLatencyMs = "compute_latency_ms"
            case isFused = "is_fused"
            case peakMemoryBytes = "peak_memory_bytes"
            case compressionRatio = "compression_ratio"
        }
    }

    struct Summary: Codable {
        let totalLatencyMs: Double
        let peakMemoryBytes: Int
        let meanCompressionRatio: Double
        let tokensPerSecond: Double

        enum CodingKeys: String, CodingKey {
            case totalLatencyMs = "total_latency_ms"
            case peakMemoryBytes = "peak_memory_bytes"
            case meanCompressionRatio = "mean_compression_ratio"
            case tokensPerSecond = "tokens_per_second"
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case model, method, bits
        case accountingOnly = "accounting_only"
        case accountingNote = "accounting_note"
        case layers, summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        model = try container.decode(String.self, forKey: .model)
        method = try container.decode(String.self, forKey: .method)
        bits = try container.decode(Int.self, forKey: .bits)
        accountingOnly = try container.decodeIfPresent(Bool.self, forKey: .accountingOnly) ?? true
        accountingNote = try container.decode(String.self, forKey: .accountingNote)
        layers = try container.decode([LayerResult].self, forKey: .layers)
        summary = try container.decode(Summary.self, forKey: .summary)
    }
}

@MainActor
final class ProfilingService: ProfilingServiceProtocol {
    private let pythonEnvironment: PythonEnvironmentService
    private let jobHistoryStore: JobHistoryStore

    init(pythonEnvironment: PythonEnvironmentService, jobHistoryStore: JobHistoryStore) {
        self.pythonEnvironment = pythonEnvironment
        self.jobHistoryStore = jobHistoryStore
    }

    func profile(request: ProfileRequest) async throws -> ProfileResponse {
        guard let interpreter = pythonEnvironment.interpreterPath else {
            throw ServiceError.pythonNotConfigured
        }

        let result = try await ProcessRunner.run(
            executable: interpreter,
            arguments: Self.profileArguments(for: request)
        )
        guard result.exitCode == 0 else {
            throw ServiceError.processFailed(result.stderr.isEmpty ? "Profiling run failed." : result.stderr)
        }
        guard let data = result.stdout.data(using: .utf8), !result.stdout.isEmpty else {
            throw ServiceError.decodingFailed
        }
        do {
            return try JSONDecoder().decode(ProfileResponse.self, from: data)
        } catch {
            throw ServiceError.decodingFailed
        }
    }

    /// Fields `cli/profile.py` forwards to `KVCacheConfig(...)` from a dedicated
    /// flag, unconditionally — `--bits` as `bit_width_inlier`. Forwarding it
    /// again via `--set` collides as a duplicate keyword argument, matching
    /// `QuantizationService.serverOwnedOverrideKeys`.
    private static let profileOwnedOverrideKeys: Set<String> = ["bit_width_inlier", "seed"]

    /// Pure argument-list builder, split out so it's unit-testable without
    /// launching a real process, matching `QuantizationService.serveArguments(for:)`.
    static func profileArguments(for request: ProfileRequest) -> [String] {
        var arguments = [
            "-m", "veloxquant_mlx", "profile",
            "--model", request.model.localPath ?? request.model.repoID,
            "--method", request.method,
            "--bits", String(request.bitWidth),
            "--prompt", request.prompt,
            "--max-tokens", String(request.maxTokens),
        ]
        for (key, value) in request.parameterOverrides where !value.isEmpty && !profileOwnedOverrideKeys.contains(key) {
            arguments.append(contentsOf: ["--set", "\(key)=\(value)"])
        }
        return arguments
    }
}
