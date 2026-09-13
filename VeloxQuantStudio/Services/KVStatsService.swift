import Foundation

/// Mirrors `build_stats_payload()` in `veloxquant_mlx/cli/telemetry.py` — the
/// JSON `GET /v1/kv/stats` returns on a running `veloxquant serve` job.
/// `keys`/`values`/`tokens` are `nil` (not zero) when nothing was reported,
/// per that function's own contract: a bare 0 and "not reported" must never
/// look the same to a user.
struct KVStats: Codable {
    let method: String?
    let bits: Int?
    let accountingOnly: Bool
    let coverage: String
    let keys: ByteCounts?
    let values: ByteCounts?
    let tokens: TokenCounts?
    let memory: Memory
    let notReportedReason: String?

    struct ByteCounts: Codable {
        let compressedBytes: Int
        let fp16Bytes: Int
        let ratio: Double?

        enum CodingKeys: String, CodingKey {
            case compressedBytes = "compressed_bytes"
            case fp16Bytes = "fp16_bytes"
            case ratio
        }
    }

    struct TokenCounts: Codable {
        let seen: Int
        let retained: Int
    }

    struct Memory: Codable {
        let rssBytes: Int?
        let mlxActiveBytes: Int?
        let mlxPeakBytes: Int?
        let source: String

        enum CodingKeys: String, CodingKey {
            case rssBytes = "rss_bytes"
            case mlxActiveBytes = "mlx_active_bytes"
            case mlxPeakBytes = "mlx_peak_bytes"
            case source
        }
    }

    enum CodingKeys: String, CodingKey {
        case method, bits
        case accountingOnly = "accounting_only"
        case coverage, keys, values, tokens, memory
        case notReportedReason = "not_reported_reason"
    }
}

@MainActor
protocol KVStatsServiceProtocol {
    /// Fetches `GET {kvStatsURL}` on a running job's server. Callers poll
    /// this themselves (e.g. on a timer while the job is `.running`) — this
    /// method makes exactly one request and returns or throws.
    func fetchStats(from kvStatsURL: URL) async throws -> KVStats
}

@MainActor
final class KVStatsService: KVStatsServiceProtocol {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func fetchStats(from kvStatsURL: URL) async throws -> KVStats {
        let (data, response) = try await urlSession.data(from: kvStatsURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.processFailed("kv/stats returned a non-200 response.")
        }
        do {
            return try JSONDecoder().decode(KVStats.self, from: data)
        } catch {
            throw ServiceError.decodingFailed
        }
    }
}
