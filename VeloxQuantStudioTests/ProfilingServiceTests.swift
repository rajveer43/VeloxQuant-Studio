import Foundation
import Testing
@testable import VeloxQuantStudio

@MainActor
struct ProfilingServiceTests {
    private func makeModel(localPath: String? = nil) -> LocalModel {
        LocalModel(repoID: "mlx-community/Llama-3.2-1B-Instruct-4bit", sizeBytes: 0, sizeLabel: "0", isMLXCommunity: true, localPath: localPath)
    }

    @Test func profileArgumentsIncludeCoreFlags() {
        let request = ProfileRequest(
            model: makeModel(),
            method: "kivi",
            bitWidth: 4,
            prompt: "hello",
            maxTokens: 32
        )
        let arguments = ProfilingService.profileArguments(for: request)

        #expect(arguments.contains("profile"))
        #expect(arguments.contains("--model"))
        #expect(arguments.contains("mlx-community/Llama-3.2-1B-Instruct-4bit"))
        #expect(arguments.contains("--method"))
        #expect(arguments.contains("kivi"))
        #expect(arguments.contains("--bits"))
        #expect(arguments.contains("4"))
        #expect(arguments.contains("--prompt"))
        #expect(arguments.contains("hello"))
        #expect(arguments.contains("--max-tokens"))
        #expect(arguments.contains("32"))
    }

    @Test func profileArgumentsPreferLocalPathOverRepoID() {
        let request = ProfileRequest(model: makeModel(localPath: "/tmp/some-model"), method: "kivi", bitWidth: 4)
        let arguments = ProfilingService.profileArguments(for: request)
        #expect(arguments.contains("/tmp/some-model"))
        #expect(!arguments.contains("mlx-community/Llama-3.2-1B-Instruct-4bit"))
    }

    @Test func profileArgumentsNeverDuplicateServerOwnedKeys() {
        let request = ProfileRequest(
            model: makeModel(),
            method: "kivi",
            bitWidth: 4,
            parameterOverrides: ["bit_width_inlier": "4", "seed": "42", "kivi_group_size": "64"]
        )
        let arguments = ProfilingService.profileArguments(for: request)

        #expect(arguments.filter { $0 == "--bits" }.count == 1)
        #expect(!arguments.contains("bit_width_inlier=4"))
        #expect(!arguments.contains("seed=42"))
        #expect(arguments.contains("kivi_group_size=64"))
    }

    @Test func profileArgumentsSkipEmptyOverrides() {
        let request = ProfileRequest(model: makeModel(), method: "kivi", bitWidth: 4, parameterOverrides: ["kivi_group_size": ""])
        let arguments = ProfilingService.profileArguments(for: request)
        #expect(!arguments.contains { $0.hasPrefix("kivi_group_size=") })
    }

    @Test func decodesResponseWithFullPayload() throws {
        let json = """
        {
          "schema_version": 1,
          "model": "mlx-community/Llama-3.2-1B-Instruct-4bit",
          "method": "turboquant_rvq",
          "bits": 4,
          "accounting_only": true,
          "accounting_note": "Compression is accounting-only.",
          "layers": [
            {"layer_index": 0, "compute_latency_ms": 4.39, "is_fused": true, "peak_memory_bytes": 23280, "compression_ratio": 0.08}
          ],
          "summary": {"total_latency_ms": 308.9, "peak_memory_bytes": 372480, "mean_compression_ratio": 0.08, "tokens_per_second": 652.1}
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(ProfileResponse.self, from: data)

        #expect(response.schemaVersion == 1)
        #expect(response.layers.count == 1)
        #expect(response.layers[0].layerIndex == 0)
        #expect(response.layers[0].isFused == true)
        #expect(response.accountingOnly == true)
        #expect(response.summary.tokensPerSecond == 652.1)
    }

    @Test func decodingDefaultsAccountingOnlyToTrueWhenMissing() throws {
        // An older CLI that omits accounting_only must not be read as a real
        // memory win — fail toward *not* overstating it (see ProfileResponse's
        // custom init(from:)).
        let json = """
        {
          "schema_version": 1,
          "model": "m",
          "method": "kivi",
          "bits": 4,
          "accounting_note": "note",
          "layers": [],
          "summary": {"total_latency_ms": 0, "peak_memory_bytes": 0, "mean_compression_ratio": 0, "tokens_per_second": 0}
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(ProfileResponse.self, from: data)
        #expect(response.accountingOnly == true)
    }

    @Test func decodingMalformedJSONThrows() {
        let data = Data("not json".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ProfileResponse.self, from: data)
        }
    }
}
