import Foundation

@MainActor
protocol BenchmarkServiceProtocol {
    /// Runs `veloxquant recommend --json` to get a hardware-aware method
    /// suggestion and an accounting-based compression estimate — this backs
    /// the Dashboard's "recommended" surface and the Benchmark screen's
    /// quick-estimate mode (no model download required).
    func recommend(request: RecommendRequest) async throws -> RecommendResponse
}

struct RecommendRequest {
    let chip: MacChipFamily
    let ramGB: Int
    let modelClass: String
    let goal: String
}

/// Mirrors `RecommendResult.to_dict()` in `veloxquant_mlx/tools/mac_recommender.py`.
struct RecommendResponse: Codable {
    let recommendation: Recommendation

    struct Recommendation: Codable {
        let method: String
        let knobs: [String: JSONValue]
        let keyAccountingRatio: Double
        let residentSavingsLikely: Bool
        let kvFP16MB: Double
        let kvCompressedMBEstimate: Double
        let warnings: [String]
        let rationale: String

        enum CodingKeys: String, CodingKey {
            case method, knobs
            case keyAccountingRatio = "key_accounting_ratio"
            case residentSavingsLikely = "resident_savings_likely"
            case kvFP16MB = "kv_fp16_mb"
            case kvCompressedMBEstimate = "kv_compressed_mb_estimate"
            case warnings, rationale
        }
    }
}

@MainActor
final class BenchmarkService: BenchmarkServiceProtocol {
    private let pythonEnvironment: PythonEnvironmentService
    private let jobHistoryStore: JobHistoryStore

    init(pythonEnvironment: PythonEnvironmentService, jobHistoryStore: JobHistoryStore) {
        self.pythonEnvironment = pythonEnvironment
        self.jobHistoryStore = jobHistoryStore
    }

    func recommend(request: RecommendRequest) async throws -> RecommendResponse {
        guard let interpreter = pythonEnvironment.interpreterPath else {
            throw ServiceError.pythonNotConfigured
        }

        let result = try await ProcessRunner.run(
            executable: interpreter,
            arguments: [
                "-m", "veloxquant_mlx", "recommend",
                "--chip", request.chip.recommenderArgument,
                "--ram-gb", String(request.ramGB),
                "--model-class", request.modelClass,
                "--goal", request.goal,
                "--json",
            ]
        )
        guard result.exitCode == 0 else {
            throw ServiceError.processFailed(result.stderr.isEmpty ? "Could not compute a recommendation." : result.stderr)
        }
        guard let data = result.stdout.data(using: .utf8) else {
            throw ServiceError.decodingFailed
        }
        return try JSONDecoder().decode(RecommendResponse.self, from: data)
    }
}
