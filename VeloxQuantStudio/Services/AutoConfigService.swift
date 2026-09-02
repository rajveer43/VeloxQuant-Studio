import Foundation

@MainActor
protocol AutoConfigServiceProtocol {
    /// Runs `veloxquant auto-config --json` — hardware-aware selection from
    /// `select_kv_cache_config()` (issue #253) over a small pool of servable
    /// methods (`turboquant_rvq`, `kivi`, `kvquant`, `gear`), given a workload
    /// shape and this Mac's memory. Requires VeloxQuant-MLX to expose the
    /// `auto-config` subcommand (added alongside this issue, #44); older
    /// interpreters will fail with `ServiceError.processFailed`.
    func recommendConfig(request: AutoConfigRequest) async throws -> AutoConfigResponse
}

struct AutoConfigRequest {
    let headDim: Int
    let seqLen: Int
    let nLayers: Int
    let batchSize: Int
    let hardware: HardwareInfo

    init(
        headDim: Int = 128,
        seqLen: Int = 4_096,
        nLayers: Int = 1,
        batchSize: Int = 1,
        hardware: HardwareInfo
    ) {
        self.headDim = headDim
        self.seqLen = seqLen
        self.nLayers = nLayers
        self.batchSize = batchSize
        self.hardware = hardware
    }
}

/// Mirrors the JSON `cli/auto_config.py` prints. `config` carries only the
/// selected method's own knob fields (`method`/`head_dim` plus that method's
/// pool-specific knobs) — every other pool method's unrelated `KVCacheConfig`
/// defaults are omitted server-side, so this never implies a knob was a
/// deliberate choice when it's really just that method's default.
struct AutoConfigResponse: Codable {
    let config: RecommendedConfig
    let reason: String

    struct RecommendedConfig: Codable {
        let method: String
        let headDim: Int
        let knobs: [String: JSONValue]

        init(method: String, headDim: Int, knobs: [String: JSONValue]) {
            self.method = method
            self.headDim = headDim
            self.knobs = knobs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            var knobs: [String: JSONValue] = [:]
            var method = ""
            var headDim = 128
            for key in container.allKeys {
                if key.stringValue == "method" {
                    method = try container.decode(String.self, forKey: key)
                } else if key.stringValue == "head_dim" {
                    headDim = try container.decode(Int.self, forKey: key)
                } else {
                    knobs[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
                }
            }
            self.method = method
            self.headDim = headDim
            self.knobs = knobs
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DynamicKey.self)
            try container.encode(method, forKey: DynamicKey(stringValue: "method")!)
            try container.encode(headDim, forKey: DynamicKey(stringValue: "head_dim")!)
            for (key, value) in knobs {
                try container.encode(value, forKey: DynamicKey(stringValue: key)!)
            }
        }

        private struct DynamicKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { self.intValue = intValue; self.stringValue = String(intValue) }
        }
    }

    enum CodingKeys: String, CodingKey {
        case config, reason
    }
}

@MainActor
final class AutoConfigService: AutoConfigServiceProtocol {
    private let pythonEnvironment: PythonEnvironmentService

    init(pythonEnvironment: PythonEnvironmentService) {
        self.pythonEnvironment = pythonEnvironment
    }

    func recommendConfig(request: AutoConfigRequest) async throws -> AutoConfigResponse {
        guard let interpreter = pythonEnvironment.interpreterPath else {
            throw ServiceError.pythonNotConfigured
        }

        let result = try await ProcessRunner.run(
            executable: interpreter,
            arguments: Self.autoConfigArguments(for: request)
        )
        guard result.exitCode == 0 else {
            throw ServiceError.processFailed(result.stderr.isEmpty ? "Could not compute an auto-config recommendation." : result.stderr)
        }
        guard let data = result.stdout.data(using: .utf8), !result.stdout.isEmpty else {
            throw ServiceError.decodingFailed
        }
        do {
            return try JSONDecoder().decode(AutoConfigResponse.self, from: data)
        } catch {
            throw ServiceError.decodingFailed
        }
    }

    /// Pure argument-list builder, split out so it's unit-testable without
    /// launching a real process, matching `ProfilingService.profileArguments(for:)`.
    ///
    /// Passes this Mac's own detected memory explicitly via
    /// `--total-memory-bytes`/`--active-memory-bytes` rather than letting the
    /// subprocess re-detect hardware through `mx.device_info()` — Studio
    /// already has this from `HardwareService` (sysctl, no MLX dependency),
    /// so there's no reason to detect it twice.
    static func autoConfigArguments(for request: AutoConfigRequest) -> [String] {
        [
            "-m", "veloxquant_mlx", "auto-config",
            "--head-dim", String(request.headDim),
            "--seq-len", String(request.seqLen),
            "--n-layers", String(request.nLayers),
            "--batch-size", String(request.batchSize),
            "--total-memory-bytes", String(request.hardware.unifiedMemoryBytes),
            "--json",
        ]
    }
}
