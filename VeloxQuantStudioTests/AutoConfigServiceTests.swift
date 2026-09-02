import Foundation
import Testing
@testable import VeloxQuantStudio

@MainActor
struct AutoConfigServiceTests {
    private func makeHardware(memoryBytes: UInt64 = 16 * 1024 * 1024 * 1024) -> HardwareInfo {
        HardwareInfo(
            chipName: "Apple M3",
            chipFamily: .m3,
            performanceCoreCount: 4,
            efficiencyCoreCount: 4,
            gpuCoreCount: nil,
            unifiedMemoryBytes: memoryBytes,
            macOSVersion: "macOS 15.0.0"
        )
    }

    @Test func autoConfigArgumentsIncludeCoreFlags() {
        let request = AutoConfigRequest(headDim: 128, seqLen: 32_000, nLayers: 4, batchSize: 2, hardware: makeHardware(memoryBytes: 17_179_869_184))
        let arguments = AutoConfigService.autoConfigArguments(for: request)

        #expect(arguments.contains("auto-config"))
        #expect(arguments.contains("--head-dim"))
        #expect(arguments.contains("128"))
        #expect(arguments.contains("--seq-len"))
        #expect(arguments.contains("32000"))
        #expect(arguments.contains("--n-layers"))
        #expect(arguments.contains("4"))
        #expect(arguments.contains("--batch-size"))
        #expect(arguments.contains("2"))
        #expect(arguments.contains("--total-memory-bytes"))
        #expect(arguments.contains("17179869184"))
        #expect(arguments.contains("--json"))
    }

    @Test func autoConfigArgumentsUseDefaultsWhenOmitted() {
        let request = AutoConfigRequest(hardware: makeHardware())
        let arguments = AutoConfigService.autoConfigArguments(for: request)
        #expect(arguments.contains("4096")) // default seqLen
        #expect(arguments.contains("1")) // default nLayers/batchSize
    }

    @Test func decodesResponseWithKnobsAndReason() throws {
        let json = """
        {
          "workload": {"head_dim": 128, "seq_len": 32000, "n_layers": 1, "batch_size": 1},
          "hardware": {"total_memory_bytes": 17179869184, "active_memory_bytes": 8},
          "config": {
            "method": "kvquant",
            "head_dim": 128,
            "kvquant_bits": 3,
            "kvquant_group_size": 32,
            "kvquant_outlier_fraction": 0.01
          },
          "reason": "seq_len=32000 >= 16384 (long context): selected kvquant (3-bit NUQ + outlier isolation) for aggressive compression"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(AutoConfigResponse.self, from: data)

        #expect(response.config.method == "kvquant")
        #expect(response.config.headDim == 128)
        if case .int(let bits) = response.config.knobs["kvquant_bits"] {
            #expect(bits == 3)
        } else {
            Issue.record("expected kvquant_bits to decode as .int")
        }
        #expect(response.reason.contains("kvquant"))
    }

    @Test func decodesResponseWithMinimalConfigFields() throws {
        // turboquant_rvq's config carries only bit_width_inlier as a knob.
        let json = """
        {
          "config": {"method": "turboquant_rvq", "head_dim": 128, "bit_width_inlier": 4},
          "reason": "short context"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(AutoConfigResponse.self, from: data)

        #expect(response.config.method == "turboquant_rvq")
        #expect(response.config.knobs.count == 1)
        #expect(response.config.knobs["kvquant_bits"] == nil)
    }

    @Test func decodingMalformedJSONThrows() {
        let data = Data("not json".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AutoConfigResponse.self, from: data)
        }
    }
}
