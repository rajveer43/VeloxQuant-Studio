import Foundation
import SwiftData

/// A quantization/benchmark job record, persisted with SwiftData for the
/// Job History screen. Independent of the live `ServerController`/process
/// state — this is the durable record of what ran, when, and with what
/// result.
@Model
final class QuantizationJob {
    @Attribute(.unique) var id: UUID
    var modelName: String
    var method: String
    var bitWidth: Int
    var parametersJSON: String
    var startedAt: Date
    var finishedAt: Date?
    var statusRaw: String
    var errorMessage: String?
    var logOutput: String

    // Benchmark results, persisted as JSON since SwiftData relationships add
    // ceremony this MVP doesn't need — one job, one result blob.
    var benchmarkResultJSON: String?

    // Profile results, same one-job-one-result-blob convention as
    // benchmarkResultJSON above. Overwritten on each re-run (see
    // JobHistoryStore.attachProfile) rather than accumulated.
    var profileResultJSON: String?

    var status: JobStatus {
        get { JobStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var duration: TimeInterval? {
        guard let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    init(
        id: UUID = UUID(),
        modelName: String,
        method: String,
        bitWidth: Int,
        parametersJSON: String = "{}",
        startedAt: Date = .now,
        finishedAt: Date? = nil,
        status: JobStatus = .running,
        errorMessage: String? = nil,
        logOutput: String = "",
        benchmarkResultJSON: String? = nil,
        profileResultJSON: String? = nil
    ) {
        self.id = id
        self.modelName = modelName
        self.method = method
        self.bitWidth = bitWidth
        self.parametersJSON = parametersJSON
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.statusRaw = status.rawValue
        self.errorMessage = errorMessage
        self.logOutput = logOutput
        self.benchmarkResultJSON = benchmarkResultJSON
        self.profileResultJSON = profileResultJSON
    }
}

enum JobStatus: String, Codable, CaseIterable {
    case running
    case succeeded
    case failed
    case cancelled

    var label: String {
        switch self {
        case .running: "Running"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

/// Before/after benchmark comparison, matching what `BenchmarkService`
/// produces from `veloxquant benchmark` + hardware/process measurements.
struct BenchmarkResult: Codable, Hashable {
    var modelSizeBeforeBytes: Int64?
    var modelSizeAfterBytes: Int64?
    var memoryUsageBeforeBytes: Int64?
    var memoryUsageAfterBytes: Int64?
    var compressionRatio: Double?
    var loadTimeBeforeSeconds: Double?
    var loadTimeAfterSeconds: Double?
    var inferenceLatencyBeforeMs: Double?
    var inferenceLatencyAfterMs: Double?
    var tokensPerSecondBefore: Double?
    var tokensPerSecondAfter: Double?
    var isAccountingOnly: Bool = true
}
