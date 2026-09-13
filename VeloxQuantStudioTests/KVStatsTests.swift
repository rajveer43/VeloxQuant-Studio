import Foundation
import Testing
@testable import VeloxQuantStudio

/// Issue #5 (`cachegen`): `KVStats` mirrors `build_stats_payload()` in
/// `veloxquant_mlx/cli/telemetry.py`. Fixtures here are the real shapes that
/// function returns — including the live one captured running
/// `veloxquant serve --method cachegen` end-to-end against a cached model.
struct KVStatsTests {
    @Test func decodesLiveCacheGenPayload() throws {
        // Captured from a real `GET /v1/kv/stats` response after serving
        // cachegen against mlx-community/Llama-3.2-1B-Instruct-4bit.
        let json = """
        {
          "method": "cachegen",
          "bits": 2,
          "accounting_only": true,
          "coverage": "keys_and_values",
          "keys": {"compressed_bytes": 0, "fp16_bytes": 0, "ratio": null},
          "values": {"compressed_bytes": 0, "fp16_bytes": 0, "ratio": null},
          "tokens": null,
          "memory": {
            "rss_bytes": 1101512704,
            "mlx_active_bytes": 712287788,
            "mlx_peak_bytes": 757745408,
            "source": "measured"
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let stats = try JSONDecoder().decode(KVStats.self, from: data)

        #expect(stats.method == "cachegen")
        #expect(stats.keys?.ratio == nil)
        #expect(stats.values?.ratio == nil)
        #expect(stats.tokens == nil)
        #expect(stats.memory.rssBytes == 1_101_512_704)
        #expect(stats.notReportedReason == nil)
    }

    @Test func decodesPopulatedRatio() throws {
        let json = """
        {
          "method": "kivi",
          "bits": 2,
          "accounting_only": true,
          "coverage": "keys_and_values",
          "keys": {"compressed_bytes": 1024, "fp16_bytes": 4096, "ratio": 4.0},
          "values": {"compressed_bytes": 1024, "fp16_bytes": 4096, "ratio": 4.0},
          "tokens": null,
          "memory": {"rss_bytes": null, "mlx_active_bytes": null, "mlx_peak_bytes": null, "source": "measured"}
        }
        """
        let data = try #require(json.data(using: .utf8))
        let stats = try JSONDecoder().decode(KVStats.self, from: data)

        #expect(stats.keys?.ratio == 4.0)
        #expect(stats.values?.compressedBytes == 1024)
    }

    /// Eviction methods (h2o, snapkv, …) report tokens seen/retained instead
    /// of byte ratios — `coverage == "none"` per `TelemetryCoverage`.
    @Test func decodesTokenCountsForEvictionMethods() throws {
        let json = """
        {
          "method": "h2o",
          "bits": null,
          "accounting_only": true,
          "coverage": "none",
          "keys": null,
          "values": null,
          "tokens": {"seen": 512, "retained": 128},
          "memory": {"rss_bytes": null, "mlx_active_bytes": null, "mlx_peak_bytes": null, "source": "measured"}
        }
        """
        let data = try #require(json.data(using: .utf8))
        let stats = try JSONDecoder().decode(KVStats.self, from: data)

        #expect(stats.keys == nil)
        #expect(stats.tokens?.seen == 512)
        #expect(stats.tokens?.retained == 128)
    }

    /// Before any request has generated — `caches is None` in
    /// `build_stats_payload()` — coverage collapses to "none" and a
    /// `not_reported_reason` explains why, rather than a bare zero.
    @Test func decodesNotReportedReasonBeforeFirstRequest() throws {
        let json = """
        {
          "method": "cachegen",
          "bits": 2,
          "accounting_only": true,
          "coverage": "none",
          "keys": null,
          "values": null,
          "tokens": null,
          "memory": {"rss_bytes": null, "mlx_active_bytes": null, "mlx_peak_bytes": null, "source": "measured"},
          "not_reported_reason": "no server is generating yet"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let stats = try JSONDecoder().decode(KVStats.self, from: data)

        #expect(stats.notReportedReason == "no server is generating yet")
        #expect(stats.keys == nil)
    }
}

@MainActor
private final class FakeKVStatsService: KVStatsServiceProtocol {
    var result: Result<KVStats, Error>
    private(set) var requestedURLs: [URL] = []

    init(result: Result<KVStats, Error>) {
        self.result = result
    }

    func fetchStats(from kvStatsURL: URL) async throws -> KVStats {
        requestedURLs.append(kvStatsURL)
        return try result.get()
    }
}

/// Issue #5: `QuantizationJobHandle` starts polling `kv/stats` once the
/// ready handshake names an endpoint, and stops when told to — this is what
/// makes the "benchmark result renders" half of the method-verification
/// checklist actually true, where before there was no such feature at all.
@MainActor
struct QuantizationJobHandleKVStatsTests {
    private func makeHandle(kvStatsService: KVStatsServiceProtocol) -> QuantizationJobHandle {
        let request = QuantizationRequest(
            model: LocalModel(repoID: "m", sizeBytes: 0, sizeLabel: "0", isMLXCommunity: false),
            method: QuantizationMethod(
                name: "cachegen", family: .quantization, serveTier: .accountingOnly,
                serveTierLabel: "available", isServable: true, blurb: "", configFields: [],
                fieldSchema: [], coverage: "none", coverageLabel: "no estimate",
                paperDeviation: nil, isAdapted: false, unsupportedReason: nil, docsURLString: nil
            ),
            bitWidth: 2, parameterOverrides: [:], port: 8971
        )
        return QuantizationJobHandle(
            request: request,
            processController: StreamingProcessController(),
            kvStatsService: kvStatsService
        )
    }

    private func readyPayload(kvStats: String?) -> ServeReadyPayload {
        ServeReadyPayload(
            schemaVersion: 2, model: "m", method: "cachegen", bits: 2, host: "127.0.0.1", port: 8971,
            layerCaches: 16,
            endpoints: .init(
                openaiBaseURL: "http://127.0.0.1:8971/v1",
                chatCompletions: "http://127.0.0.1:8971/v1/chat/completions",
                completions: "http://127.0.0.1:8971/v1/completions",
                models: "http://127.0.0.1:8971/v1/models",
                kvStats: kvStats
            ),
            accountingOnly: true, accountingNote: "compression is accounting-only."
        )
    }

    @Test func markingReadyStartsPollingAndPopulatesStats() async throws {
        let stats = KVStats(
            method: "cachegen", bits: 2, accountingOnly: true, coverage: "keys_and_values",
            keys: .init(compressedBytes: 0, fp16Bytes: 0, ratio: nil), values: nil, tokens: nil,
            memory: .init(rssBytes: nil, mlxActiveBytes: nil, mlxPeakBytes: nil, source: "measured"),
            notReportedReason: nil
        )
        let service = FakeKVStatsService(result: .success(stats))
        let handle = makeHandle(kvStatsService: service)

        handle.markReadyForTesting(readyPayload(kvStats: "http://127.0.0.1:8971/v1/kv/stats"))
        try await Task.sleep(for: .milliseconds(50))

        #expect(handle.kvStats?.method == "cachegen")
        #expect(service.requestedURLs.first?.absoluteString == "http://127.0.0.1:8971/v1/kv/stats")

        handle.stopPollingKVStats()
    }

    @Test func markingReadyWithoutKVStatsEndpointNeverPolls() async throws {
        let service = FakeKVStatsService(result: .failure(URLError(.badURL)))
        let handle = makeHandle(kvStatsService: service)

        handle.markReadyForTesting(readyPayload(kvStats: nil))
        try await Task.sleep(for: .milliseconds(50))

        #expect(handle.kvStats == nil)
        #expect(service.requestedURLs.isEmpty)
    }

    @Test func fetchFailureSurfacesAsKVStatsError() async throws {
        let service = FakeKVStatsService(result: .failure(URLError(.timedOut)))
        let handle = makeHandle(kvStatsService: service)

        handle.markReadyForTesting(readyPayload(kvStats: "http://127.0.0.1:8971/v1/kv/stats"))
        try await Task.sleep(for: .milliseconds(50))

        #expect(handle.kvStatsError != nil)
        #expect(handle.kvStats == nil)

        handle.stopPollingKVStats()
    }
}
